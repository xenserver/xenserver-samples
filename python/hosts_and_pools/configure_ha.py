"""Configure high availability.

Turn on pool High Availability: choose a shared SR as the heartbeat statefile, compute how many host
failures the pool can tolerate, enable HA, then disable it again.

Run it::

    configure_ha("https://xenserver", "root", password, "Shared NFS")
"""

from connection import connect
from helpers import sr_by_name


def configure_ha(url, username, password, heartbeat_sr_name):
    """Enable pool HA on the named shared heartbeat SR, then disable it again."""
    session = connect(url, username, password)
    pool_ref = list(session.xenapi.pool.get_all_records().keys())[0]

    # The HA heartbeat statefile needs a shared SR; confirm the chosen one can host it.
    sr_ref = sr_by_name(session, heartbeat_sr_name, shared=True)
    print("Heartbeat SR:  %s" % session.xenapi.SR.get_name_label(sr_ref))
    session.xenapi.SR.assert_can_host_ha_statefile(sr_ref)

    # What HA does per VM. The restart priority decides which guests come back first after a host
    # failure, and whether a VM is protected at all; "restart" is protected, an empty string is not.
    guest = next(ref for ref, r in session.xenapi.VM.get_all_records().items()
                 if not r["is_a_template"] and not r["is_control_domain"] and not r["is_a_snapshot"])

    # How many host failures can the pool tolerate WITH the VMs you mean to protect? Plan for those: a
    # target computed with none protected can be too high, and protecting a VM afterwards then fails
    # HA_OPERATION_WOULD_BREAK_FAILOVER_PLAN.
    ntol = session.xenapi.pool.ha_compute_hypothetical_max_host_failures_to_tolerate({guest: "restart"})
    print("Max failures:  %s" % ntol)
    session.xenapi.pool.set_ha_host_failures_to_tolerate(pool_ref, ntol)
    session.xenapi.pool.enable_ha([sr_ref], {})
    try:
        print("HA enabled:    %s" % session.xenapi.pool.get_ha_enabled(pool_ref))

        was = session.xenapi.VM.get_ha_restart_priority(guest)
        session.xenapi.VM.set_ha_restart_priority(guest, "restart")
        print("%s priority: %r -> %r"
              % (session.xenapi.VM.get_name_label(guest), was,
                 session.xenapi.VM.get_ha_restart_priority(guest)))
        session.xenapi.VM.set_ha_restart_priority(guest, was)

        # And a pool-wide judgement call: if a guest shuts itself down from the inside, is that a
        # failure HA should undo, or an administrator's intent it should respect?
        internal = session.xenapi.pool.get_ha_reboot_vm_on_internal_shutdown(pool_ref)
        print("Restart on internal shutdown: %s" % internal)
    finally:
        # Turn HA back off however the above went: left on, it blocks host reboots, coordinator
        # changes and more (HA_IS_ENABLED, HA_OPERATION_WOULD_BREAK_FAILOVER_PLAN).
        session.xenapi.pool.disable_ha()
    print("HA enabled:    %s" % session.xenapi.pool.get_ha_enabled(pool_ref))
    print("OK: configure-ha")
    session.xenapi.session.logout()
