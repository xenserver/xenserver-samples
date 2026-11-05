# Manage a vApp.
#
# Group VMs into an appliance that starts and stops together in a defined order, start and shut it down as a
# unit, then remove it.
#
# Run it:
#   ./workflows.sh manage-vapp https://xenserver root "$password"
#
# Optional key=value arguments (default):
#   vm_name (db-01)

manage_vapp() {
    local vm_uuid vapp_uuid
    # A halted VM: an appliance starts only if one of its VMs is halted (OPERATION_NOT_ALLOWED otherwise).
    vm_uuid=$(xe vm-list name-label="$(param vm_name db-01)" --minimal)
    vapp_uuid=$(xe appliance-create name-label=sdk-example-vapp \
        name-description="Created by the SDK example")

    # `order` decides the sequence: ascending to start, descending to shut down. That ordering is the
    # reason to use a vApp rather than selecting several VMs.
    xe vm-param-set uuid="$vm_uuid" appliance="$vapp_uuid" order=0 start-delay=5

    xe appliance-start uuid="$vapp_uuid"
    echo "Started:        $(xe vm-list uuid="$vm_uuid" params=power-state --minimal)"

    # A plain appliance-shutdown tries a clean shutdown of every member and fails
    # OPERATION_PARTIALLY_FAILED if any member can't shut down cleanly (no guest OS or PV drivers);
    # force=true is not a per-member fallback - it hard-shuts-down every member directly - so only
    # reach for it if the clean attempt failed.
    xe appliance-shutdown uuid="$vapp_uuid" || xe appliance-shutdown uuid="$vapp_uuid" force=true
    echo "Shut down:      $(xe vm-list uuid="$vm_uuid" params=power-state --minimal)"

    xe vm-param-set uuid="$vm_uuid" appliance=
    xe appliance-destroy uuid="$vapp_uuid"
    echo "OK: manage-vapp"
}
