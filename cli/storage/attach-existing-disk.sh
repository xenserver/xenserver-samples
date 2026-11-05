# Attach an existing disk to another VM.
#
# Move a disk between VMs by detaching and re-attaching it, without copying the data.
#
# Run it:
#   ./workflows.sh attach-existing-disk https://xenserver root "$password"

attach_existing_disk() {
    # A disk and the VM it belongs to are separate objects joined by a VBD, so moving a disk between VMs
    # is removing one VBD and creating another - no copying, and the data stays exactly where it is.
    halted=$(xe vm-list power-state=halted --minimal)
    first=$(nth_csv "$halted" 1)
    second=$(nth_csv "$halted" 2)
    sr=$(default_sr)

    vdi=$(xe vdi-create sr-uuid=$sr name-label=xe-example-portable-disk virtual-size=4294967296 type=user)
    echo "Disk $(xe vdi-param-get uuid=$vdi param-name=name-label) created on $(xe sr-param-get uuid=$sr param-name=name-label)"

    device=$(first_csv "$(set_to_csv "$(xe vm-param-get uuid=$first param-name=allowed-VBD-devices)")")
    vbd=$(xe vbd-create vm-uuid=$first vdi-uuid=$vdi device=$device type=Disk mode=RW)
    echo "  attached to $(xe vm-param-get uuid=$first param-name=name-label)"

    # Destroying the VBD detaches the disk; the disk itself is untouched and keeps its data.
    xe vbd-destroy uuid=$vbd
    echo "  detached:   the disk still exists ($(xe vdi-param-get uuid=$vdi param-name=virtual-size) bytes)"

    device=$(first_csv "$(set_to_csv "$(xe vm-param-get uuid=$second param-name=allowed-VBD-devices)")")
    vbd2=$(xe vbd-create vm-uuid=$second vdi-uuid=$vdi device=$device type=Disk mode=RW)
    echo "  attached to $(xe vm-param-get uuid=$second param-name=name-label)"
    echo "  the disk is on $(count_csv "$(set_to_csv "$(xe vdi-param-get uuid=$vdi param-name=vbds)")") VM(s)"

    xe vbd-destroy uuid=$vbd2
    xe vdi-destroy uuid=$vdi
    echo "OK: attach-existing-disk"
}
