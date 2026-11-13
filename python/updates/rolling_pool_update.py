"""Rolling pool update.

Apply the CDN's updates across the pool with zero downtime: sync the metadata, then for each host in
turn - coordinator first - apply the updates (evacuating its VMs first only if that turns out to be
needed), reboot if asked to, and re-enable it — host-by-host orchestration.

Run it::

    rolling_pool_update("https://xenserver", "root", password, "https://repo.ops.xenserver.com/xs9",
    "https://repo-src.ops.xenserver.com/xs9")
"""

import XenAPI

from connection import connect
from helpers import enable_when_booted, introduce_update_repositories, wait_for_restart


def rolling_pool_update(url, username, password, repo_url, source_url):
    """Apply the CDN's updates host-by-host, coordinator first, so the pool never goes fully offline.

    Host.apply_updates refuses with HA_IS_ENABLED while HA is on, and the documentation also asks
    for Workload Balancing to be switched off before you start updating - so check both up front and
    stop rather than disabling either for you; turn them back on again once the update is done.
    Needs an enabled update repository the same way apply-update does - introduce and attach a
    throwaway one, forget it again afterwards. Modern xapi (>=23.18.0) doesn't reboot a host for
    you: it only records pending_guidances, so only reboot (or restart the toolstack) when the
    applied batch actually asks for it, and only evacuate a host first if applying without doing so
    fails with HOST_EVACUATION_IS_REQUIRED - most updates don't need it. Guidance that targets VMs
    instead of hosts (for example restarting a VM) is not handled here."""
    session = connect(url, username, password)
    pool = session.xenapi.pool.get_all()[0]
    if session.xenapi.pool.get_ha_enabled(pool) or session.xenapi.pool.get_wlb_enabled(pool):
        raise RuntimeError("HA and Workload Balancing must both be off before updating the pool; "
                            "disable them, run this again, then re-enable them once it finishes")
    repos = introduce_update_repositories(session, repo_url, source_url)
    # Remember the pool's own repositories, to put them back afterwards.
    previous = session.xenapi.pool.get_repositories(pool)
    session.xenapi.pool.set_repositories(pool, repos)
    try:
        hash_ = session.xenapi.pool.sync_updates(pool, False, "", "")
        print("Synced updates; hash length %d" % len(hash_))

        # The rolling pattern: apply -> evacuate and retry only if that turns out to be needed ->
        # reboot (only if asked) -> re-enable, one host at a time, coordinator first.
        hosts = session.xenapi.host.get_all_records()
        master = session.xenapi.pool.get_master(pool)
        ordered_refs = [master] + [ref for ref in hosts if ref != master]
        for host_ref in ordered_refs:
            host = hosts[host_ref]
            print("Updating %s:" % host["name_label"])
            try:
                session.xenapi.host.apply_updates(host_ref, hash_)  # apply the synced updates
            except XenAPI.Failure as e:
                if e.details[0] != "HOST_EVACUATION_IS_REQUIRED":
                    raise
                print("  needs evacuating first; evacuating and retrying")
                session.xenapi.host.disable(host_ref)   # stop new VMs landing here
                session.xenapi.host.evacuate(host_ref)  # move running guests to the rest of the pool
                session.xenapi.host.apply_updates(host_ref, hash_)
                session.xenapi.host.enable(host_ref)
            guidance = session.xenapi.host.get_pending_guidances(host_ref)
            print("  applied; pending guidance = [%s]" % ", ".join(guidance))
            if "reboot_host" in guidance or "restart_toolstack" in guidance:
                # Either restart returns before it has happened, and if this host is the coordinator
                # it takes this session with it - so note when the host last started, restart it, and
                # reconnect until it reports a newer start and is live again.
                key = "boot_time" if "reboot_host" in guidance else "agent_start_time"
                before = session.xenapi.host.get_other_config(host_ref).get(key)
                if key == "boot_time":
                    session.xenapi.host.reboot(host_ref)       # reboot into the updated software
                else:
                    session.xenapi.host.restart_agent(host_ref)
                session = wait_for_restart(url, username, password, host["uuid"], key, before)
            enable_when_booted(session.xenapi, host_ref)       # return the host to service
    finally:
        session.xenapi.pool.set_repositories(pool, previous)
        for repo in repos:
            session.xenapi.Repository.forget(repo)
    print("OK: rolling-pool-update")
    session.xenapi.session.logout()
