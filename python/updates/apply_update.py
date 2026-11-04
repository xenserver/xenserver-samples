"""Apply updates from the CDN.

Sync the pool's update metadata from the CDN and apply it to every host, then read each host's post-
update reboot guidance.

Run it::

    apply_update("https://xenserver", "root", password, "https://repo.ops.xenserver.com/xs9",
    "https://repo-src.ops.xenserver.com/xs9")
"""

import XenAPI

from connection import connect
from helpers import enable_when_booted, introduce_update_repositories, wait_for_restart


def apply_update(url, username, password, repo_url, source_url):
    """Sync the pool's update metadata from the CDN, then apply the synced updates to each host.

    pool.sync_updates needs at least one repository with update=True enabled
    (NO_REPOSITORY_ENABLED otherwise) - introduce and attach a throwaway one, and forget it again
    afterwards. Applying a batch whose mandatory guidance needs an evacuation fails with
    HOST_EVACUATION_IS_REQUIRED unless the host's resident VMs are moved off first; handle that
    rather than assuming an update batch never asks for one, and resolve any pending mandatory
    guidance before finishing (it would otherwise block the next apply_updates on that host with
    HOST_PENDING_MANDATORY_GUIDANCES_NOT_EMPTY)."""
    session = connect(url, username, password)
    pool = session.xenapi.pool.get_all()[0]
    repos = introduce_update_repositories(session, repo_url, source_url)
    # Remember the pool's own repositories, to put them back afterwards.
    previous = session.xenapi.pool.get_repositories(pool)
    session.xenapi.pool.set_repositories(pool, repos)
    try:
        # Sync the pool's update metadata; the returned hash identifies the synced set.
        hash_ = session.xenapi.pool.sync_updates(pool, False, "", "")
        print("Synced updates; hash length %d" % len(hash_))

        # Apply the synced updates to each host. XenCenter then reads the reboot guidance to decide
        # whether a Rolling Pool Upgrade reboot is needed.
        for host_ref, host in session.xenapi.host.get_all_records().items():
            try:
                session.xenapi.host.apply_updates(host_ref, hash_)
            except XenAPI.Failure as e:
                if e.details[0] != "HOST_EVACUATION_IS_REQUIRED":
                    raise
                print("  %s: needs evacuating first; evacuating and retrying" % host["name_label"])
                session.xenapi.host.disable(host_ref)
                session.xenapi.host.evacuate(host_ref)
                session.xenapi.host.apply_updates(host_ref, hash_)
                session.xenapi.host.enable(host_ref)
            guidance = session.xenapi.host.get_pending_guidances(host_ref)
            print("  %s: applied; pending guidance = [%s]" % (host["name_label"], ", ".join(guidance)))
            if "reboot_host" in guidance or "restart_toolstack" in guidance:
                # As in rolling-pool-update: either restart returns before it has happened, and the
                # coordinator's takes this session with it - so wait for it, reconnecting.
                key = "boot_time" if "reboot_host" in guidance else "agent_start_time"
                before = session.xenapi.host.get_other_config(host_ref).get(key)
                if key == "boot_time":
                    session.xenapi.host.reboot(host_ref)
                else:
                    session.xenapi.host.restart_agent(host_ref)
                session = wait_for_restart(url, username, password, host["uuid"], key, before)
            # apply_updates disables the host while it works (auto_enable: a restart puts it back) - with
            # no restart to do, nothing re-enables it. Return it to service either way.
            enable_when_booted(session.xenapi, host_ref)
    finally:
        session.xenapi.pool.set_repositories(pool, previous)
        for repo in repos:
            session.xenapi.Repository.forget(repo)
    print("OK: apply-update")
    session.xenapi.session.logout()
