"""Checkpoint & revert.

Take a checkpoint of a running VM (disk AND memory, unlike a plain snapshot) and revert to it, as
you would before a risky in-guest change. A checkpoint needs the guest's cooperation, so the VM must
have a guest OS with PV drivers (vm_name).

Run it::

    checkpoint_vm("https://xenserver", "root", password, "web-01")
"""

from connection import connect
from helpers import destroy_vm_and_disks, vm_by_name, wait_for_guest_agent


def checkpoint_vm(url, username, password, vm_name):
    """A checkpoint captures disk AND memory (unlike a plain snapshot), so the VM must be running.
    Checkpoint vm_name, revert it to that checkpoint, and resume it.

    Checkpointing needs the guest's cooperation (VM_LACKS_FEATURE without PV drivers): the guest
    freezes its processes and suspends itself. A guest that is still booting can fail to freeze a
    process that is busy starting up, and it then abandons the suspend without telling the host, which
    waits until VM_SUSPEND_TIMEOUT - so checkpoint a VM that has finished booting, as here."""
    session = connect(url, username, password)
    vm = vm_by_name(session, vm_name)
    if session.xenapi.VM.get_power_state(vm) != "Running":
        raise RuntimeError("%s must be running to be checkpointed" % vm_name)
    # Running is not enough: the VM may have just been started (or restarted, as snapshot-revert does), so
    # wait for its guest to finish booting first.
    wait_for_guest_agent(session, vm)

    checkpoint = session.xenapi.VM.checkpoint(vm, "sdk-example-checkpoint-1")
    print("Created checkpoint: %s" % session.xenapi.VM.get_uuid(checkpoint))
    print("is_a_snapshot = %s" % session.xenapi.VM.get_is_a_snapshot(checkpoint))

    session.xenapi.VM.revert(checkpoint)
    # A checkpoint's own power_state is always Suspended (it captures memory as well as disk), and
    # VM.revert restores exactly that - so the VM is Suspended here, not Running as it was before
    # the checkpoint, with a suspend_VDI holding the checkpoint's memory image. VM.resume picks up
    # from there (and frees that memory image).
    print("Reverted %s to the checkpoint; power state now: %s"
          % (vm_name, session.xenapi.VM.get_power_state(vm)))
    session.xenapi.VM.resume(vm, False, True)
    print("Resumed %s; power state now: %s" % (vm_name, session.xenapi.VM.get_power_state(vm)))

    # Tidy up. The checkpoint owns its own snapshot disks, separate from the VM's.
    destroy_vm_and_disks(session, checkpoint)
    print("Deleted the checkpoint.")
    print("OK: checkpoint-vm")
    session.logout()
