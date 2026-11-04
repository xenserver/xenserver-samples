"""Clone a VM.

Make a fast copy-on-write clone of a VM on the same storage repository — distinct from a full copy —
the quick way to stamp out new VMs from a halted "golden" image.

Run it::

    clone_vm("https://xenserver", "root", password, "db-01")
"""

from connection import connect
from helpers import destroy_vm_and_disks, vm_by_name


def clone_vm(url, username, password, vm_name, clone_name="sdk-example-clone"):
    """Fast copy-on-write clone of a halted VM (unlike Copy, which is a full, independent copy
    onto a chosen SR). Ideal for duplicating a halted "golden" VM on the same SR."""
    session = connect(url, username, password)
    source = vm_by_name(session, vm_name)
    clone = session.xenapi.VM.clone(source, clone_name)
    print("Cloned '%s' -> %s"
          % (session.xenapi.VM.get_name_label(source), session.xenapi.VM.get_name_label(clone)))
    print("Clone has %d VBD(s)" % len(session.xenapi.VM.get_VBDs(clone)))

    # Tidy up: destroy the clone and its (owned) disks.
    destroy_vm_and_disks(session, clone)
    print("OK: clone-vm")
    session.xenapi.session.logout()
