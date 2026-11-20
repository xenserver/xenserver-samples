"""Copy a VM.

Make a full, independent copy of a VM onto a chosen storage repository (a deep copy of its disks) —
distinct from a fast, copy-on-write clone.

Run it::

    copy_vm("https://xenserver", "root", password, "db-01", "Shared NFS")
"""

from connection import connect
from helpers import destroy_vm_and_disks, sr_by_name, vm_by_name


def copy_vm(url, username, password, vm_name, sr_name, copy_name="sdk-example-copy"):
    """Make a full, independent copy of the named VM onto the named SR (a deep copy of its disks).

    VM.copy (like VM.clone) only works on a Halted VM - a running source fails with
    VM_BAD_POWER_STATE - so shut it down first if it's running, and start it back up again after
    the copy, rather than assuming the VM is already halted."""
    session = connect(url, username, password)
    # A full copy needs a halted source; it places an independent set of disks on the chosen SR.
    source = vm_by_name(session, vm_name)
    sr_ref = sr_by_name(session, sr_name)
    print("Copying '%s' to SR: %s"
          % (session.xenapi.VM.get_name_label(source), session.xenapi.SR.get_name_label(sr_ref)))

    was_running = session.xenapi.VM.get_power_state(source) == "Running"
    if was_running:
        session.xenapi.VM.clean_shutdown(source)

    copy = session.xenapi.VM.copy(source, copy_name, sr_ref)
    print("Copied VM:     %s" % session.xenapi.VM.get_uuid(copy))
    print("Copy has %d VBD(s), is_a_template = %s"
          % (len(session.xenapi.VM.get_VBDs(copy)), session.xenapi.VM.get_is_a_template(copy)))

    if was_running:
        session.xenapi.VM.start(source, False, True)

    # Tidy up: destroy the copy and its disks, leaving the source VM intact.
    destroy_vm_and_disks(session, copy)
    print("Cleaned up the copied VM (left the source intact).")
    print("OK: copy-vm")
    session.xenapi.session.logout()
