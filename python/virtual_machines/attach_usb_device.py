"""Attach a USB device to a VM.

List the USB devices a host exposes, enable passthrough on one, attach it to a VM and detach it
again.

Run it::

    attach_usb_device("https://xenserver", "root", password, "web-01")
"""

from connection import connect


def attach_usb_device(url, username, password, vm_name):
    """Enable passthrough on a host USB device, attach it to a VM, then detach it.

    VUSB.destroy refuses a VUSB that is still attached (OPERATION_NOT_ALLOWED) - on a running VM
    it gets plugged in as soon as it's created, so unplug it first, the same unplug-before-destroy
    shape SR.forget and VBD/PBD teardown already need elsewhere in this file."""
    session = connect(url, username, password)
    x = session.xenapi
    vm = x.VM.get_by_name_label(vm_name)[0]

    pusb_ref, pusb = next(iter(x.PUSB.get_all_records().items()))
    print(f"Device:         {pusb['description']}")

    # Passthrough is off until an administrator enables it on the device: attaching one that has not
    # been released fails rather than silently doing nothing.
    x.PUSB.set_passthrough_enabled(pusb_ref, True)

    vusb = x.VUSB.create(vm, pusb["USB_group"], {})
    print(f"Attached:       {len(x.VM.get_VUSBs(vm))} device(s)")

    if x.VUSB.get_currently_attached(vusb):
        x.VUSB.unplug(vusb)
    x.VUSB.destroy(vusb)
    x.PUSB.set_passthrough_enabled(pusb_ref, False)
    print("OK: attach-usb-device")
    x.session.logout()
