"""Apply updates from the CDN.

Sync the pool's update metadata from the CDN and apply it to one host - the pool coordinator, unless
you name another - then act on that host's post-update guidance.

Run it::

    apply_update("https://xenserver", "root", password, "https://repo.ops.xenserver.com/xs9",
    "https://repo-src.ops.xenserver.com/xs9")
"""

from connection import connect
from helpers import apply_updates_to_host, attach_update_repository, detach_update_repository


def apply_update(url, username, password, repo_url, source_url, host_name=""):
    """Sync the pool's update metadata from the CDN, then apply the synced updates to one host: the
    one named `host_name`, or the coordinator if no name is given.

    The documentation asks for the coordinator to be updated before any other host, so update it
    first, then run this again naming each of the others - or use rolling-pool-update to do the
    whole pool in one go. helpers.attach_update_repository checks that HA and Workload Balancing are
    off and attaches a throwaway update repository, which pool.sync_updates needs; it is forgotten
    again afterwards. helpers.apply_updates_to_host does the rest: evacuating the host first if that
    turns out to be needed, acting on its post-update guidance, and returning it to service."""
    session = connect(url, username, password)
    pool = session.xenapi.pool.get_all()[0]
    if host_name:
        hosts = session.xenapi.host.get_by_name_label(host_name)
        if len(hosts) != 1:
            raise RuntimeError("expected one host named %r, found %d" % (host_name, len(hosts)))
        host_ref = hosts[0]
    else:
        host_ref = session.xenapi.pool.get_master(pool)
    name = session.xenapi.host.get_name_label(host_ref)

    repo, previous = attach_update_repository(session, pool, repo_url, source_url)
    try:
        # Sync the pool's update metadata; the returned hash identifies the synced set.
        hash_ = session.xenapi.pool.sync_updates(pool, False, "", "")
        print("Synced updates; hash length %d" % len(hash_))
        session = apply_updates_to_host(session, url, username, password, host_ref, hash_,
                                        label="%s: " % name)
    finally:
        detach_update_repository(session, pool, repo, previous)
    print("OK: apply-update")
    session.xenapi.session.logout()
