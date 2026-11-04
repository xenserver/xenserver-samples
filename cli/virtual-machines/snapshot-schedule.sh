# Snapshot schedule.
#
# Create a scheduled-snapshot policy, attach a VM to it, run it on demand and watch the retention limit prune
# the oldest snapshot away.
#
# Run it:
#   ./workflows.sh snapshot-schedule https://xenserver root "$password"

snapshot_schedule() {
    vm=$(vm_uuid web-01)
    # retained-snapshots is the interesting field: the schedule prunes to it every time it runs.
    vmss=$(xe vmss-create name-label=xe-example-schedule type=snapshot frequency=daily retained-snapshots=2)
    echo "Created schedule: $vmss"

    xe vm-param-set uuid=$vm snapshot-schedule=$vmss
    echo "Members:          $(count_csv "$(set_to_csv "$(xe vmss-param-get uuid=$vmss param-name=VMs)")")"

    # xe has no command to run a schedule on demand (the API's VMSS.snapshot_now has no CLI form), so it
    # takes its first snapshot when it next falls due, and from then on keeps the newest retained-snapshots.
    echo "Keeps:            $(xe vmss-param-get uuid=$vmss param-name=retained-snapshots) snapshot(s)"

    # A schedule with VMs still on it cannot be destroyed, so take the VM off it first.
    xe vm-param-set uuid=$vm snapshot-schedule=
    xe vmss-destroy uuid=$vmss
    echo "OK: snapshot-schedule"
}
