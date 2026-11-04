"""VM power lifecycle.

Drive a VM through its power states — start it, suspend it to memory, resume it and shut it down
cleanly. Suspend and clean shutdown need the guest's cooperation, so this works on a throwaway copy
of a VM with a guest OS and PV drivers (source_vm), which is deleted again with its disks
afterwards.
"""

from connection import connect
from helpers import copy_of_guest, destroy_vm_and_disks, wait_for_guest_agent


def vm_lifecycle(url, username, password, source_vm, new_vm_name="sdk-example-lifecycle"):
    """Take a throwaway copy of a VM with a guest OS through start -> suspend -> resume -> clean
    shutdown, and delete it again.

    Suspend and clean shutdown need the guest's cooperation (VM_LACKS_FEATURE without PV drivers),
    so the copy is made from source_vm, a VM with a guest OS and PV drivers, and the example waits
    for the guest to report in after starting. Suspend also needs a suspend-image SR (the VM's own,
    else the pool's, else the host's); check one is actually configured before trying."""
    session = connect(url, username, password)
    vm_ref = copy_of_guest(session, source_vm, new_vm_name)

    def state():
        return session.xenapi.VM.get_power_state(vm_ref)

    print("Initial power state: %s" % state())
    session.xenapi.VM.start(vm_ref, False, True)
    wait_for_guest_agent(session, vm_ref)
    print("After start:   %s" % state())

    # The emulated hardware (the device model) can be restarted under a running guest without
    # rebooting it -- what you reach for when the VM's virtual devices misbehave.
    session.xenapi.VM.restart_device_models(vm_ref)
    print("Device models restarted; still %s" % state())

    if _has_suspend_sr(session, vm_ref):
        session.xenapi.VM.suspend(vm_ref)
        print("After suspend: %s" % state())
        session.xenapi.VM.resume(vm_ref, False, True)
        wait_for_guest_agent(session, vm_ref)   # the PV drivers reconnect after a resume
        print("After resume:  %s" % state())
    else:
        print("Skipping suspend/resume: no suspend-image SR is configured for this VM/pool/host")

    # A clean shutdown asks the guest OS to shut itself down, as pressing the power button would.
    session.xenapi.VM.clean_shutdown(vm_ref)
    print("After shutdown:%s" % state())

    destroy_vm_and_disks(session, vm_ref)
    print("OK: vm-lifecycle")
    session.xenapi.session.logout()


def _has_suspend_sr(session, vm):
    """Whether VM.suspend has a suspend-image SR to use: the VM's own, else the pool's, else the
    resident host's - the same fallback order xapi's choose_suspend_sr uses."""
    x = session.xenapi
    if x.VM.get_suspend_SR(vm) != "OpaqueRef:NULL":
        return True
    pool = x.pool.get_all()[0]
    if x.pool.get_suspend_image_SR(pool) != "OpaqueRef:NULL":
        return True
    host = x.pool.get_master(pool)
    return x.host.get_suspend_image_sr(host) != "OpaqueRef:NULL"
