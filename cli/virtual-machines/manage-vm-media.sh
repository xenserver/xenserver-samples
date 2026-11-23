# Manage a VM's CD drive.
#
# Add a DVD drive to a VM, insert an ISO from the library and eject it again.
#
# Run it:
#   ./workflows.sh manage-vm-media https://xenserver root "$password"

manage_vm_media() {
    vm=$(nth_csv "$(remote_xe vm-list power-state=halted --minimal)" 1)
    [ -n "$vm" ] || { echo "no halted VM to give a DVD drive to" >&2; return 1; }

    # Find an ISO image before changing the VM, so a pool without one fails before it does.
    # An ISO library is an SR of type iso; its VDIs are the images. Take the first library that holds any
    # (type=iso as well as content-type=iso: a host's physical DVD drive is content-type iso too, but it
    # is type udev and holds whatever disc is in the tray rather than a library of images).
    local iso_sr iso=""
    for iso_sr in $(each_csv "$(remote_xe sr-list content-type=iso type=iso --minimal)"); do
        iso=$(nth_csv "$(remote_xe vdi-list sr-uuid=$iso_sr --minimal)" 1)
        [ -n "$iso" ] && break
    done
    [ -n "$iso" ] || { echo "no ISO library with an image in it was found" >&2; return 1; }

    echo "Adding a DVD drive to $(remote_xe vm-param-get uuid=$vm param-name=name-label)"
    # A CD drive is a VBD like any other, distinguished by type=CD; created without a disk it arrives
    # empty, and the media is whichever VDI it is later pointed at.
    device=$(first_csv "$(set_to_csv "$(remote_xe vm-param-get uuid=$vm param-name=allowed-VBD-devices)")")
    drive=$(remote_xe vbd-create vm-uuid=$vm device=$device type=CD mode=RO)
    echo "  drive $device is empty: $(remote_xe vbd-param-get uuid=$drive param-name=empty)"

    echo "  inserting $(remote_xe vdi-param-get uuid=$iso param-name=name-label)"
    remote_xe vbd-insert uuid=$drive vdi-uuid=$iso
    echo "  drive now holds $(remote_xe vdi-param-get uuid=$(remote_xe vbd-param-get uuid=$drive param-name=vdi-uuid) param-name=name-label) (empty=$(remote_xe vbd-param-get uuid=$drive param-name=empty))"

    remote_xe vbd-eject uuid=$drive
    echo "  after eject, empty=$(remote_xe vbd-param-get uuid=$drive param-name=empty)"

    remote_xe vbd-destroy uuid=$drive
    ok manage-vm-media
}
