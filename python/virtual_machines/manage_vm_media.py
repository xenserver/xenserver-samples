"""Manage a VM's CD drive.

Add a DVD drive to a VM, insert an ISO from the library and eject it again.

Run it::

    manage_vm_media("https://xenserver", "root", password)
"""

from connection import connect


def manage_vm_media(url, username, password):
    """Give a VM a DVD drive, put an ISO in it, then eject it.

    A CD drive is a VBD like any other, distinguished by type=CD; the media is whichever
    VDI it points at, and an empty drive points at none."""
    session = connect(url, username, password)
    x = session.xenapi

    vm = next(ref for ref, v in x.VM.get_all_records().items()
              if not v["is_a_template"] and not v["is_control_domain"]
              and not v["is_a_snapshot"] and v["power_state"] == "Halted")
    print("Adding a DVD drive to %s" % x.VM.get_name_label(vm))

    device = x.VM.get_allowed_VBD_devices(vm)[0]
    drive = x.VBD.create({
        "VM": vm, "VDI": "OpaqueRef:NULL", "userdevice": device, "bootable": False,
        "mode": "RO", "type": "CD", "empty": True, "unpluggable": True,
        "other_config": {}, "qos_algorithm_type": "", "qos_algorithm_params": {},
    })
    print("  drive %s is empty: %s" % (device, x.VBD.get_empty(drive)))

    # The ISO library is an SR of content type "iso"; its VDIs are the available images.
    iso_sr = next(ref for ref, s in x.SR.get_all_records().items()
                  if s["content_type"] == "iso" and s["type"] != "udev")
    iso = sorted(x.SR.get_VDIs(iso_sr), key=lambda v: x.VDI.get_name_label(v))[0]
    print("  inserting %s" % x.VDI.get_name_label(iso))
    x.VBD.insert(drive, iso)
    print("  drive now holds %s (empty=%s)"
          % (x.VDI.get_name_label(x.VBD.get_VDI(drive)), x.VBD.get_empty(drive)))

    x.VBD.eject(drive)
    print("  after eject, empty=%s" % x.VBD.get_empty(drive))

    x.VBD.destroy(drive)
    print("OK: manage-vm-media")
    session.logout()
