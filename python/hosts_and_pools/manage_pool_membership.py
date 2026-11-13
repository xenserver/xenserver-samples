"""Manage pool membership.

List the pool's member hosts and which one coordinates it, promote a different host to coordinator,
then promote the original back.

Run it::

    manage_pool_membership("https://xenserver", "root", password)
"""

import time

from connection import connect


def manage_pool_membership(url, username, password):
    """List the pool's hosts, promote a different coordinator, then promote the original back.

    designate_new_master runs a two-phase commit across every host and ends by restarting xapi
    pool-wide (the new coordinator becomes master, every other host becomes its slave) - so the
    session this call was made on, and the connection itself, do not survive it. Reconnect (with a
    bounded wait, since xapi is briefly unavailable while it restarts) before touching the pool
    again, rather than assuming the session is still good."""
    session = connect(url, username, password)
    x = session.xenapi
    pool = x.pool.get_all()[0]

    hosts = x.host.get_all_records()
    original = x.pool.get_master(pool)
    print(f"Coordinator: {hosts[original]['name_label']}")
    for ref, host in hosts.items():
        print(f"  member: {host['name_label']}" + (" (coordinator)" if ref == original else ""))

    # Promote another member. The pool database moves with the role and clients are redirected, so this
    # briefly interrupts management traffic — it does not move any VM.
    other = next(ref for ref in hosts if ref != original)
    x.pool.designate_new_master(other)
    print(f"Promoting:   {hosts[other]['name_label']} (xapi restarts pool-wide; reconnecting)")

    session = _reconnect_after_master_change(url, username, password, hosts[other]["uuid"])
    x = session.xenapi
    pool = x.pool.get_all()[0]
    print(f"Promoted:    {x.host.get_name_label(x.pool.get_master(pool))}")

    # Put it back. Ejecting a member (pool.eject) is the other half of this surface and is deliberately
    # not shown: it cannot be undone from the pool, because rejoining is initiated by the ejected host.
    x.pool.designate_new_master(original)
    print(f"Restoring:   {hosts[original]['name_label']} (reconnecting again)")

    session = _reconnect_after_master_change(url, username, password, hosts[original]["uuid"])
    x = session.xenapi
    pool = x.pool.get_all()[0]
    print(f"Restored:    {x.host.get_name_label(x.pool.get_master(pool))}")

    print("OK: manage-pool-membership")
    x.session.logout()


def _reconnect_after_master_change(url, username, password, new_master_uuid, timeout=600, interval=5):
    """Wait out a pool-wide xapi restart (pool.designate_new_master) and reconnect.

    designate_new_master returns BEFORE the change: for a while the old coordinator still answers,
    and still says it is the coordinator, until xapi restarts across the pool. So reconnecting is not
    enough - keep reconnecting until the pool names the new coordinator (by uuid; connect() follows
    HOST_IS_SLAVE to wherever the coordinator now is). That can take minutes."""
    deadline = time.time() + timeout
    last_error = None
    while time.time() < deadline:
        try:
            session = connect(url, username, password)
            x = session.xenapi
            master = x.pool.get_master(x.pool.get_all()[0])
            # The new coordinator answers before the pool has settled - calls made too soon fail
            # (HANDLE_INVALID on the operation's own task) - so also wait for every host to be back,
            # live and enabled.
            if x.host.get_uuid(master) == new_master_uuid and all(
                    r["enabled"] and x.host_metrics.get_live(r["metrics"])
                    for r in x.host.get_all_records().values()):
                return session
            x.session.logout()
            last_error = "the pool has not settled under the new coordinator"
        except Exception as e:
            last_error = e
        time.sleep(interval)
    raise RuntimeError("the pool did not come back after the master change: %s" % last_error)
