"""Checkpoint & revert.

Take a checkpoint of a running VM (disk AND memory, unlike a plain snapshot) and revert to it, as
you would before a risky in-guest change. A checkpoint needs the guest's cooperation, so this works
on a throwaway copy of a VM with a guest OS and PV drivers (source_vm).

Run it::

    checkpoint_vm("https://xenserver", "root", password, "web-01")
"""

from connection import connect
from helpers import copy_of_guest, destroy_vm_and_disks, wait_for_guest_agent


def checkpoint_vm(url, username, password, source_vm, new_vm_name="sdk-example-checkpoint"):
    """A checkpoint captures disk AND memory (unlike a plain snapshot), so the VM must be running.
    Checkpoint a throwaway copy of a VM with a guest OS, then revert it back to that checkpoint.

    Checkpointing needs the guest's cooperation (VM_LACKS_FEATURE without PV drivers), hence a copy
    of source_vm - a VM with a guest OS and PV drivers - rather than an OS-less template clone."""
    session = connect(url, username, password)
    vm = copy_of_guest(session, source_vm, new_vm_name)
    session.xenapi.VM.start(vm, False, True)
    wait_for_guest_agent(session, vm)

    checkpoint = session.xenapi.VM.checkpoint(vm, "sdk-example-checkpoint-1")
    print("Created checkpoint: %s" % session.xenapi.VM.get_uuid(checkpoint))
    print("is_a_snapshot = %s" % session.xenapi.VM.get_is_a_snapshot(checkpoint))

    session.xenapi.VM.revert(checkpoint)
    # A checkpoint's own power_state is always Suspended (it captures memory as well as disk), and
    # VM.revert restores exactly that - so the VM is Suspended here, not Running as it was before
    # the checkpoint, with a suspend_VDI holding the checkpoint's memory image. VM.resume clears
    # that: destroying a Suspended VM directly (as a bare "if Running: hard_shutdown" check would,
    # since the VM is never Running here) leaves that suspend_VDI behind as a storage leak.
    print("Reverted the VM to the checkpoint; power state now: %s"
          % session.xenapi.VM.get_power_state(vm))
    session.xenapi.VM.resume(vm, False, True)

    # Tidy up. The checkpoint owns its own snapshot disks, separate from the VM's.
    destroy_vm_and_disks(session, checkpoint)
    session.xenapi.VM.hard_shutdown(vm)
    destroy_vm_and_disks(session, vm)
    print("OK: checkpoint-vm")
    session.xenapi.session.logout()
