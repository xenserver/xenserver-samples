"""Delete a VM.

Remove a VM and its owned disks: deleting a VM leaves its disks behind, so the disks are destroyed
explicitly afterward.

Run it::

    delete_vm("https://xenserver", "root", password, "Rocky Linux 8")
"""

from connection import connect
from helpers import disk_vdis, provision, template_by_name


def delete_vm(url, username, password, template_name, new_vm_name="sdk-example-delete"):
    """Make a throwaway VM, then delete it: VM.destroy removes the VM but leaves its disks, so the
    owned VDIs are destroyed explicitly afterward — exactly what XenCenter's Delete VM does."""
    session = connect(url, username, password)
    vm = session.xenapi.VM.clone(template_by_name(session, template_name), new_vm_name)
    provision(session, vm)
    uuid = session.xenapi.VM.get_uuid(vm)
    vdis = disk_vdis(session, vm)
    print("Deleting VM %s with %d disk(s)" % (uuid, len(vdis)))

    session.xenapi.VM.destroy(vm)
    for vdi in vdis:
        session.xenapi.VDI.destroy(vdi)

    still_there = any(r["uuid"] == uuid for r in session.xenapi.VM.get_all_records().values())
    print("VM still present: %s" % still_there)
    print("OK: delete-vm")
    session.xenapi.session.logout()
