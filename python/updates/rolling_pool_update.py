"""Rolling pool update.

Apply the CDN's updates to every host in the pool without stopping its VMs: one host at a time,
coordinator first, move the host's VMs to the rest of the pool, apply the updates, restart it if the
update asks for that, and return it to service.

Run it::

    rolling_pool_update("https://xenserver", "root", password, "https://repo.ops.xenserver.com/xs9",
    "https://repo-src.ops.xenserver.com/xs9")
"""

from connection import connect
from helpers import apply_updates_to_host, attach_update_repository, detach_update_repository


def rolling_pool_update(url, username, password, repo_url, source_url):
    """Update the whole pool host by host, coordinator first, moving each host's VMs off it before
    updating it, so the VMs keep running throughout.

    Check first that every host can be emptied: host.get_vms_which_prevent_evacuation names the VMs
    that could not move anywhere else (for example a VM with a disk on the host's local storage, or
    a pool with nowhere else to put them) - stop before changing anything if there are any. Then,
    for each host: disable it so nothing new starts there, evacuate it (live-migrating its VMs to
    the other hosts), and let helpers.apply_updates_to_host apply the updates, restart the host or
    its toolstack if the update asks for that, and enable it again. The VMs stay where evacuation
    put them. helpers.attach_update_repository checks that HA and Workload Balancing are off and
    attaches a throwaway update repository, which pool.sync_updates needs; it is forgotten again
    afterwards."""
    session = connect(url, username, password)
    pool = session.xenapi.pool.get_all()[0]
    master = session.xenapi.pool.get_master(pool)
    hosts = [master] + [ref for ref in session.xenapi.host.get_all() if ref != master]
    for host_ref in hosts:
        blocking = session.xenapi.host.get_vms_which_prevent_evacuation(host_ref)
        if blocking:
            names = ", ".join(session.xenapi.VM.get_name_label(vm) for vm in blocking)
            raise RuntimeError("%s cannot be evacuated: move or shut down %s first"
                               % (session.xenapi.host.get_name_label(host_ref), names))

    repo, previous = attach_update_repository(session, pool, repo_url, source_url)
    try:
        hash_ = session.xenapi.pool.sync_updates(pool, False, "", "")
        print("Synced updates; hash length %d" % len(hash_))
        for host_ref in hosts:
            print("Updating %s: moving its VMs to the rest of the pool"
                  % session.xenapi.host.get_name_label(host_ref))
            session.xenapi.host.disable(host_ref)
            session.xenapi.host.evacuate(host_ref)
            session = apply_updates_to_host(session, url, username, password, host_ref, hash_)
    finally:
        detach_update_repository(session, pool, repo, previous)
    print("OK: rolling-pool-update")
    session.xenapi.session.logout()
