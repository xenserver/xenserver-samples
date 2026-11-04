"""Manage VM groups.

Create an anti-affinity VM group, put a VM in it, read the membership back from the group side, then
take the VM out again and delete the group.

Run it::

    manage_vm_groups("https://xenserver", "root", password, "web-01")
"""

from connection import connect
from helpers import vm_by_name


def manage_vm_groups(url, username, password, vm_name, group_name="sdk-example-group"):
    """Create an anti-affinity VM group, add a VM, read the membership back, then tidy up."""
    session = connect(url, username, password)
    vm_ref = vm_by_name(session, vm_name)

    # anti_affinity asks the pool to keep the group's members on different hosts.
    group_ref = session.xenapi.VM_group.create({
        "name_label": group_name,
        "name_description": "Anti-affinity group created by the SDK example",
        "placement": "anti_affinity",
    })
    print("Created group:  %s" % session.xenapi.VM_group.get_uuid(group_ref))

    # Membership is written from the VM side...
    session.xenapi.VM.set_groups(vm_ref, [group_ref])

    # ...and read back from the group side, which is the half that is easy to get wrong.
    members = session.xenapi.VM_group.get_VMs(group_ref)
    print("Group members:  %d" % len(members))
    for m in members:
        print("  %s" % session.xenapi.VM.get_name_label(m))

    # VM_group.destroy already clears the group from every member VM's groups field - no need to
    # remove membership ourselves first.
    session.xenapi.VM_group.destroy(group_ref)
    print("OK: manage-vm-groups")
    session.xenapi.session.logout()
