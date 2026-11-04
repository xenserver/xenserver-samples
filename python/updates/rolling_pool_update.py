"""Rolling pool update.

Apply the CDN's updates across the pool with zero downtime: sync the metadata, then for each host in
turn disable it, evacuate its VMs to the rest of the pool, apply the updates, reboot, and re-enable
it — host-by-host orchestration.

Run it::

    rolling_pool_update("https://xenserver", "root", password, "https://repo.ops.xenserver.com/xs9",
    "https://repo-src.ops.xenserver.com/xs9")
"""

from connection import connect
from helpers import enable_when_booted, introduce_update_repositories, wait_for_restart


def rolling_pool_update(url, username, password, repo_url, source_url):
    """Apply the CDN's updates host-by-host so the pool never goes fully offline.

    Needs an enabled update repository the same way apply-update does - introduce and attach a
    throwaway one, forget it again afterwards. Modern xapi (>=23.18.0) doesn't reboot a host for
    you: it only records pending_guidances, so only reboot (or restart the toolstack) when the
    applied batch actually asks for it."""
    session = connect(url, username, password)
    pool = session.xenapi.pool.get_all()[0]
    repos = introduce_update_repositories(session, repo_url, source_url)
    # Remember the pool's own repositories, to put them back afterwards.
    previous = session.xenapi.pool.get_repositories(pool)
    session.xenapi.pool.set_repositories(pool, repos)
    try:
        hash_ = session.xenapi.pool.sync_updates(pool, False, "", "")
        print("Synced updates; hash length %d" % len(hash_))

        # The rolling pattern behind XenCenter's automated Install Updates:
        # disable -> evacuate -> apply -> reboot (only if asked) -> re-enable, one host at a time.
        for host_ref, host in session.xenapi.host.get_all_records().items():
            print("Updating %s:" % host["name_label"])
            session.xenapi.host.disable(host_ref)               # stop new VMs landing here
            session.xenapi.host.evacuate(host_ref)              # move running guests to the rest of the pool
            session.xenapi.host.apply_updates(host_ref, hash_)  # apply the synced updates
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
