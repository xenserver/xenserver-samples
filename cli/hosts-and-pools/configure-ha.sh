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
    pool=$(xe pool-list --minimal)
    # xe has no command to check in advance that the chosen SR can host the HA heartbeat statefile
    # (the SDK's SR.assert_can_host_ha_statefile); pool-ha-enable below fails on its own if it can't.

    # What HA does per VM. The restart priority decides which guests come back first after a host
    # failure, and whether a VM is protected at all; "restart" is protected, an empty string is not.
    guest=$(first_csv "$(xe vm-list is-a-template=false is-control-domain=false is-a-snapshot=false --minimal)")

    # How many host failures can the pool tolerate WITH the VMs you mean to protect? Plan for those: a target
    # computed with none protected can be too high, and protecting a VM afterwards then fails
    # HA_OPERATION_WOULD_BREAK_FAILOVER_PLAN.
    ntol=$(xe pool-ha-compute-hypothetical-max-host-failures-to-tolerate vm-uuid=$guest restart-priority=restart)
    echo "Max failures: $ntol"
    xe pool-param-set uuid=$pool ha-host-failures-to-tolerate=$ntol

    xe pool-ha-enable heartbeat-sr-uuids=$(sr_by_name "$(param heartbeat_sr_name "Shared NFS")")
    echo "HA enabled: $(xe pool-param-get uuid=$pool param-name=ha-enabled)"

    was=$(xe vm-param-get uuid=$guest param-name=ha-restart-priority)
    xe vm-param-set uuid=$guest ha-restart-priority=restart
    echo "$(xe vm-param-get uuid=$guest param-name=name-label) priority: '$was' -> '$(xe vm-param-get uuid=$guest param-name=ha-restart-priority)'"
    xe vm-param-set uuid=$guest ha-restart-priority="$was"

    # And a pool-wide judgement call: if a guest shuts itself down from the inside, is that a
    # failure HA should undo, or an administrator's intent it should respect?
    echo "Restart on internal shutdown: $(xe pool-param-get uuid=$pool param-name=ha-reboot-vm-on-internal-shutdown)"

    xe pool-ha-disable
    echo "HA enabled: $(xe pool-param-get uuid=$pool param-name=ha-enabled)"
    echo "OK: configure-ha"
}
