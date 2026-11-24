"""Rolling pool update.

Apply the CDN's updates to every host in the pool without stopping its VMs: one host at a time,
coordinator first, move the host's VMs to the rest of the pool, apply the updates, restart it if the
update asks for that, and return it to service.

Run it::

    rolling_pool_update("https://xenserver", "root", password, "https://repo.ops.xenserver.com/xs9",
    "https://repo-src.ops.xenserver.com/xs9")
"""

from connection import connect
from helpers import (attach_update_repository, check_hosts_can_be_evacuated, check_no_pending_guidance,
                     detach_update_repository, hosts_coordinator_first, report_vm_guidance, update_hosts)


def rolling_pool_update(url, username, password, repo_url, source_url):
    """Update the whole pool host by host, coordinator first, moving each host's VMs off it before
    updating it, so the VMs keep running throughout.

    Check first, before changing anything, that the update can go through: no host or VM may still
    have mandatory guidance pending from an earlier update, and every host must be able to empty
    (helpers.check_no_pending_guidance, helpers.check_hosts_can_be_evacuated). Then sync, and let
    helpers.update_hosts update each host in turn: disable it, evacuate it, apply the updates,
    restart it or its toolstack if the update asks for that, and enable it again. Finally report the
    guidance left for VMs, such as restarting one to pick the update up - that is the VM owner's
    call. helpers.attach_update_repository checks that HA and Workload Balancing are off and
    attaches a throwaway update repository, which pool.sync_updates needs; it is forgotten again
    afterwards."""
    session = connect(url, username, password)
    pool = session.xenapi.pool.get_all()[0]
    hosts = hosts_coordinator_first(session)
    check_no_pending_guidance(session)
    check_hosts_can_be_evacuated(session, hosts)

    repo, previous = attach_update_repository(session, pool, repo_url, source_url)
    try:
        hash_ = session.xenapi.pool.sync_updates(pool, False, "", "")
        print("Synced updates; hash length %d" % len(hash_))
        session = update_hosts(session, url, username, password, hosts, hash_)
    finally:
        detach_update_repository(session, pool, repo, previous)
    report_vm_guidance(session)
    print("OK: rolling-pool-update")
    session.xenapi.session.logout()
