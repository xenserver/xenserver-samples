# Attach a USB device to a VM.
#
# List the USB devices a host exposes, enable passthrough on one, attach it to a VM and detach it again.
#
# Run it:
#   ./workflows.sh attach-usb-device https://xenserver root "$password"

attach_usb_device() {
    local vm_uuid pusb_uuid group_uuid vusb_uuid
    vm_uuid=$(xe vm-list name-label=web-01 --minimal)
    pusb_uuid=$(first_csv "$(xe pusb-list --minimal)")
    echo "Device:         $(xe pusb-list uuid="$pusb_uuid" params=product-desc --minimal)"

    # Passthrough is off until an administrator releases the device: attaching one that has not been
    # released fails rather than silently doing nothing.
    xe pusb-param-set uuid="$pusb_uuid" passthrough-enabled=true

    group_uuid=$(xe pusb-list uuid="$pusb_uuid" params=usb-group-uuid --minimal)
    vusb_uuid=$(xe vusb-create vm-uuid="$vm_uuid" usb-group-uuid="$group_uuid")
    echo "Attached:       $(count_csv "$(xe vusb-list vm-uuid="$vm_uuid" --minimal)") device(s)"

    # vusb-destroy refuses a VUSB that is still attached (OPERATION_NOT_ALLOWED) - on a running VM it gets
    # plugged in as soon as it's created, so unplug it first.
    if [ "$(xe vusb-param-get uuid="$vusb_uuid" param-name=currently-attached)" = "true" ]; then
        xe vusb-unplug uuid="$vusb_uuid"
    fi
    xe vusb-destroy uuid="$vusb_uuid"
    xe pusb-param-set uuid="$pusb_uuid" passthrough-enabled=false
    echo "OK: attach-usb-device"
}
