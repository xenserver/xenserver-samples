"""Manage a VM's CD drive.

Add a DVD drive to a VM, insert an ISO from the library and eject it again.

Run it::

    manage_vm_media("https://xenserver", "root", password)
"""

from connection import connect
from helpers import NULL_REF


def manage_vm_media(url, username, password):
    """Give a VM a DVD drive, put an ISO in it, then eject it.

    A CD drive is a VBD like any other, distinguished by type=CD; the media is whichever
    VDI it points at, and an empty drive points at none."""
    session = connect(url, username, password)
    x = session.xenapi

    vm = next((ref for ref, v in x.VM.get_all_records().items()
               if not v["is_a_template"] and not v["is_control_domain"]
               and not v["is_a_snapshot"] and v["power_state"] == "Halted"), None)
    if vm is None:
        raise RuntimeError("no halted VM to give a DVD drive to")

    # Find an ISO image before changing the VM, so a pool without one fails before it does.
    # An ISO library is an SR of content type "iso"; its VDIs are the images. Take the first
    # library that holds any (a host's physical DVD drive is content type iso too, but type udev).
    images = []
    for ref, s in x.SR.get_all_records().items():
        if s["content_type"] == "iso" and s["type"] != "udev":
            images = x.SR.get_VDIs(ref)
            if images:
                break
    if not images:
        raise RuntimeError("no ISO library with an image in it was found")
    iso = sorted(images, key=lambda v: x.VDI.get_name_label(v))[0]

    print("Adding a DVD drive to %s" % x.VM.get_name_label(vm))
    device = x.VM.get_allowed_VBD_devices(vm)[0]
    drive = x.VBD.create({
        "VM": vm, "VDI": NULL_REF, "userdevice": device, "bootable": False,
        "mode": "RO", "type": "CD", "empty": True, "unpluggable": True,
        "other_config": {}, "qos_algorithm_type": "", "qos_algorithm_params": {},
    })
    print("  drive %s is empty: %s" % (device, x.VBD.get_empty(drive)))

    print("  inserting %s" % x.VDI.get_name_label(iso))
    x.VBD.insert(drive, iso)
    print("  drive now holds %s (empty=%s)"
          % (x.VDI.get_name_label(x.VBD.get_VDI(drive)), x.VBD.get_empty(drive)))

    x.VBD.eject(drive)
    print("  after eject, empty=%s" % x.VBD.get_empty(drive))

    x.VBD.destroy(drive)
    print("OK: manage-vm-media")
    session.logout()
