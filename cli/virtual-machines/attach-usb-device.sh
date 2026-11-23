# Attach a USB device to a VM.
#
# List the USB devices a host exposes, enable passthrough on one, attach it to a VM and detach it again.
#
# Run it:
#   ./workflows.sh attach-usb-device https://xenserver root "$password"

attach_usb_device() {
    local vm_uuid pusb_uuid group_uuid vusb_uuid p desc key best_key
    vm_uuid=$(remote_xe vm-list name-label=web-01 --minimal)
    # Pick deterministically (lowest description, then uuid), not whatever order the server lists them in.
    pusb_uuid="" best_key=""
    for p in $(each_csv "$(remote_xe pusb-list --minimal)"); do
        # param-get, not --minimal: --minimal escapes any comma in the value ("Ours Technology\, Inc.").
        desc=$(remote_xe pusb-param-get uuid="$p" param-name=description)
        key="$desc"$'\t'"$p"
        if [ -z "$pusb_uuid" ] || [[ "$key" < "$best_key" ]]; then
            best_key=$key; pusb_uuid=$p
        fi
    done
    echo "Device:         $(remote_xe pusb-param-get uuid="$pusb_uuid" param-name=description)"

    # Passthrough is off until an administrator releases the device: attaching one that has not been
    # released fails rather than silently doing nothing.
    remote_xe pusb-param-set uuid="$pusb_uuid" passthrough-enabled=true

    group_uuid=$(remote_xe pusb-list uuid="$pusb_uuid" params=usb-group-uuid --minimal)
    vusb_uuid=$(remote_xe vusb-create vm-uuid="$vm_uuid" usb-group-uuid="$group_uuid")
    echo "Attached:       $(count_csv "$(remote_xe vusb-list vm-uuid="$vm_uuid" --minimal)") device(s)"

    # vusb-destroy refuses a VUSB that is still attached (OPERATION_NOT_ALLOWED) - on a running VM it gets
    # plugged in as soon as it's created, so unplug it first.
    if [ "$(remote_xe vusb-param-get uuid="$vusb_uuid" param-name=currently-attached)" = "true" ]; then
        remote_xe vusb-unplug uuid="$vusb_uuid"
    fi
    remote_xe vusb-destroy uuid="$vusb_uuid"
    echo "Detached:       $(count_csv "$(remote_xe vusb-list vm-uuid="$vm_uuid" --minimal)") device(s)"
    remote_xe pusb-param-set uuid="$pusb_uuid" passthrough-enabled=false
    ok attach-usb-device
}
