"""Attach a new disk.

Create a fresh virtual disk on a storage repository and attach it to a VM.

Run it::

    attach_disk("https://xenserver", "root", password, "Rocky Linux 8", "Shared NFS")
"""

from connection import connect
from helpers import destroy_vm_and_disks, provision, sr_by_name, template_by_name


def attach_disk(url, username, password, template_name, sr_name, new_vm_name="sdk-example-attachdisk"):
    """Provision a VM, then create a fresh VDI on the named SR and attach it as a new virtual disk."""
    GIB = 1024 * 1024 * 1024
    session = connect(url, username, password)
    vm = session.xenapi.VM.clone(template_by_name(session, template_name), new_vm_name)
    provision(session, vm)
    sr_ref = sr_by_name(session, sr_name)

    vdi = session.xenapi.VDI.create({
        "name_label": "sdk-example-data-disk",
        "SR": sr_ref,
        "virtual_size": str(8 * GIB),
        "type": "user",
        "sharable": False,
        "read_only": False,
        "other_config": {},
    })
    device = session.xenapi.VM.get_allowed_VBD_devices(vm)[0]
    session.xenapi.VBD.create({
        "VM": vm, "VDI": vdi, "userdevice": device,
        "bootable": False,
        "mode": "RW", "type": "Disk", "empty": False, "other_config": {},
        "qos_algorithm_type": "", "qos_algorithm_params": {},
    })
    print("Attached an 8 GiB disk on %s as device %s"
          % (session.xenapi.SR.get_name_label(sr_ref), device))
    print("VM now has %d VBD(s)" % len(session.xenapi.VM.get_VBDs(vm)))

    # Tidy up: destroy the VM (which removes its VBDs) and then its disks (VM.destroy leaves VDIs
    # behind), including the one just attached.
    destroy_vm_and_disks(session, vm)
    print("OK: attach-disk")
    session.xenapi.session.logout()
