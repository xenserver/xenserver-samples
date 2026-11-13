"""Create a VM and a template from a snapshot.

Turn a snapshot into a new VM that stands on its own, and into a reusable custom template.

Run it::

    vm_from_snapshot("https://xenserver", "root", password, "db-01")
"""

from connection import connect
from helpers import destroy_vm_and_disks, provision, vm_by_name


def vm_from_snapshot(url, username, password, vm_name="db-01"):
    """Turn a snapshot into a new VM, and into a reusable custom template.

    A snapshot is a VM record with is_a_snapshot (and is_a_template) set, and cloning it gives a
    custom template that stands on its own while the snapshot stays put. That clone already is the
    template; provisioning another clone turns it into a VM, exactly as with any template."""
    session = connect(url, username, password)
    x = session.xenapi

    vm = vm_by_name(session, vm_name)
    snapshot = x.VM.snapshot(vm, "sdk-example-source-snapshot")
    print("Snapshot of %s taken" % vm_name)

    # A clone of a snapshot is a template, not another snapshot: it stands on its own instead of
    # being filed under the original VM. Provision it to get an ordinary VM you can start.
    new_vm = x.VM.clone(snapshot, "sdk-example-vm-from-snapshot")
    provision(session, new_vm)
    print("  new VM:      %s (is_a_template=%s)"
          % (x.VM.get_name_label(new_vm), x.VM.get_is_a_template(new_vm)))

    # Another clone, left as the template it already is: a starting point to stamp more VMs from.
    template = x.VM.clone(snapshot, "sdk-example-template-from-snapshot")
    print("  new template:%s (is_a_template=%s)"
          % (x.VM.get_name_label(template), x.VM.get_is_a_template(template)))

    # Each clone made its own disks, and the snapshot has its own snapshot disks; destroy them all.
    for ref in (new_vm, template):
        destroy_vm_and_disks(session, ref)
    destroy_vm_and_disks(session, snapshot)
    print("OK: vm-from-snapshot")
    session.logout()
