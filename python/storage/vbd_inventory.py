"""Inventory a VM's disks.

List a VM's attached disks and the size of each.

Run it::

    vbd_inventory("https://xenserver", "root", password, "db-01")
"""

from connection import connect
from helpers import vm_by_name


def vbd_inventory(url, username, password, vm_name):
    """List the named VM's disk VBDs and the size of each backing VDI."""
    GIB = 1024 * 1024 * 1024
    session = connect(url, username, password)
    vm = vm_by_name(session, vm_name)
    print("Disks of '%s':" % session.xenapi.VM.get_name_label(vm))
    for vbd in session.xenapi.VM.get_VBDs(vm):
        if session.xenapi.VBD.get_type(vbd) != "Disk":
            continue
        vdi = session.xenapi.VBD.get_VDI(vbd)
        size = 0 if vdi == "OpaqueRef:NULL" else int(session.xenapi.VDI.get_virtual_size(vdi)) // GIB
        print("  - device %s: %d GiB" % (session.xenapi.VBD.get_userdevice(vbd), size))
    print("OK: vbd-inventory")
    session.xenapi.session.logout()
