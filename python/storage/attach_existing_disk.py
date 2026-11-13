"""Attach an existing disk to another VM.

Move a disk between VMs by detaching and re-attaching it, without copying the data.
"""

from connection import connect


def attach_existing_disk(url, username, password):
    """Move an existing disk from one VM to another by re-attaching it.

    A disk and the VM it belongs to are separate objects joined by a VBD, so moving a disk
    between VMs is removing one VBD and creating another -- no copying, and the data stays
    exactly where it is. This is how you recover a disk from a VM you are retiring."""
    GIB = 1024 * 1024 * 1024
    session = connect(url, username, password)
    x = session.xenapi

    halted = [ref for ref, r in x.VM.get_all_records().items()
              if not r["is_a_template"] and not r["is_control_domain"] and not r["is_a_snapshot"]
              and r["power_state"] == "Halted"]
    first, second = halted[0], halted[1]

    sr = next(ref for ref, r in x.SR.get_all_records().items()
              if r["shared"] and r["content_type"] != "iso" and r["type"] not in ("iso", "udev"))
    vdi = x.VDI.create({
        "name_label": "sdk-example-portable-disk",
        "SR": sr, "virtual_size": str(4 * GIB), "type": "user",
        "sharable": False, "read_only": False, "other_config": {},
    })
    print("Disk %s created on %s" % (x.VDI.get_name_label(vdi), x.SR.get_name_label(sr)))

    vbd = attach_vdi(x, first, vdi)
    print("  attached to %s" % x.VM.get_name_label(first))

    # Destroying the VBD detaches the disk; the disk itself is untouched and keeps its data.
    x.VBD.destroy(vbd)
    print("  detached:   the disk still exists (%d bytes)" % int(x.VDI.get_virtual_size(vdi)))

    attach_vdi(x, second, vdi)
    print("  attached to %s" % x.VM.get_name_label(second))
    print("  the disk is on %d VM(s)" % len(x.VDI.get_VBDs(vdi)))

    for ref in x.VDI.get_VBDs(vdi):
        x.VBD.destroy(ref)
    x.VDI.destroy(vdi)
    print("OK: attach-existing-disk")
    session.logout()


def attach_vdi(x, vm, vdi):
    """Join an existing disk to a VM on its next free device slot."""
    return x.VBD.create({
        "VM": vm, "VDI": vdi, "userdevice": x.VM.get_allowed_VBD_devices(vm)[0],
        "bootable": False,
        "mode": "RW", "type": "Disk", "empty": False, "other_config": {},
        "qos_algorithm_type": "", "qos_algorithm_params": {},
    })
