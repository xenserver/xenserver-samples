# Manage a VM's CD drive.
#
# Add a DVD drive to a VM, insert an ISO from the library and eject it again.
#
# Run it:
#   ./workflows.sh manage-vm-media https://xenserver root "$password"

manage_vm_media() {
    vm=$(nth_csv "$(xe vm-list power-state=halted --minimal)" 1)
    echo "Adding a DVD drive to $(xe vm-param-get uuid=$vm param-name=name-label)"

    # A CD drive is a VBD like any other, distinguished by type=CD; created without a disk it arrives
    # empty, and the media is whichever VDI it is later pointed at.
    device=$(first_csv "$(set_to_csv "$(xe vm-param-get uuid=$vm param-name=allowed-VBD-devices)")")
    drive=$(xe vbd-create vm-uuid=$vm device=$device type=CD mode=RO)
    echo "  drive $device is empty: $(xe vbd-param-get uuid=$drive param-name=empty)"

    # The ISO library is an SR of content type "iso"; its VDIs are the available images.
    # type=iso as well as content-type=iso: a host's physical DVD drive is content-type iso too, but it
    # is type udev and holds whatever disc is in the tray rather than a library of images.
    iso_sr=$(nth_csv "$(xe sr-list content-type=iso type=iso --minimal)" 1)
    iso=$(nth_csv "$(xe vdi-list sr-uuid=$iso_sr --minimal)" 1)
    echo "  inserting $(xe vdi-param-get uuid=$iso param-name=name-label)"
    xe vbd-insert uuid=$drive vdi-uuid=$iso
    echo "  drive now holds $(xe vdi-param-get uuid=$(xe vbd-param-get uuid=$drive param-name=vdi-uuid) param-name=name-label) (empty=$(xe vbd-param-get uuid=$drive param-name=empty))"

    xe vbd-eject uuid=$drive
    echo "  after eject, empty=$(xe vbd-param-get uuid=$drive param-name=empty)"

    xe vbd-destroy uuid=$drive
    echo "OK: manage-vm-media"
}
