# Configure high availability.
#
# Turn on pool High Availability: choose a shared SR as the heartbeat statefile, compute how many host
# failures the pool can tolerate, enable HA, then disable it again.
#
# Run it:
#   ./workflows.sh configure-ha https://xenserver root "$password"
#
# Optional key=value arguments (default):
#   heartbeat_sr_name (Shared NFS)

configure_ha() {
    pool=$(remote_xe pool-list --minimal)
    # xe has no command to check in advance that the chosen SR can host the HA heartbeat statefile
    # (the SDK's SR.assert_can_host_ha_statefile); pool-ha-enable below fails on its own if it can't.

    # What HA does per VM. The restart priority decides which guests come back first after a host
    # failure, and whether a VM is protected at all; "restart" is protected, an empty string is not.
    guest=$(first_csv "$(remote_xe vm-list is-a-template=false is-control-domain=false is-a-snapshot=false --minimal)")

    # How many host failures can the pool tolerate WITH the VMs you mean to protect? Plan for those: a target
    # computed with none protected can be too high, and protecting a VM afterwards then fails
    # HA_OPERATION_WOULD_BREAK_FAILOVER_PLAN.
    ntol=$(remote_xe pool-ha-compute-hypothetical-max-host-failures-to-tolerate vm-uuid=$guest restart-priority=restart)
    echo "Max failures: $ntol"
    remote_xe pool-param-set uuid=$pool ha-host-failures-to-tolerate=$ntol

    heartbeat_sr=$(sr_by_name "$(param heartbeat_sr_name "Shared NFS")")
    echo "Heartbeat SR: $(remote_xe sr-param-get uuid=$heartbeat_sr param-name=name-label)"
    remote_xe pool-ha-enable heartbeat-sr-uuids=$heartbeat_sr
    # Turn HA back off however the rest of this goes: left on, it blocks host reboots, coordinator
    # changes and more (HA_IS_ENABLED, HA_OPERATION_WOULD_BREAK_FAILOVER_PLAN).
    trap 'remote_xe_try pool-ha-disable' EXIT
    echo "HA enabled: $(remote_xe pool-param-get uuid=$pool param-name=ha-enabled)"

    was=$(remote_xe vm-param-get uuid=$guest param-name=ha-restart-priority)
    remote_xe vm-param-set uuid=$guest ha-restart-priority=restart
    echo "$(remote_xe vm-param-get uuid=$guest param-name=name-label) priority: '$was' -> '$(remote_xe vm-param-get uuid=$guest param-name=ha-restart-priority)'"
    remote_xe vm-param-set uuid=$guest ha-restart-priority="$was"

    # And a pool-wide judgement call: if a guest shuts itself down from the inside, is that a
    # failure HA should undo, or an administrator's intent it should respect?
    echo "Restart on internal shutdown: $(remote_xe pool-param-get uuid=$pool param-name=ha-reboot-vm-on-internal-shutdown)"

    remote_xe pool-ha-disable
    trap - EXIT
    echo "HA enabled: $(remote_xe pool-param-get uuid=$pool param-name=ha-enabled)"
    ok configure-ha
}
