"""Live migrate a VM.

Move a running VM to another host in the pool with no downtime: check the destination can boot it,
live-migrate it and confirm where it now runs. Uses a throwaway copy of a VM with a guest OS and PV
drivers (source_vm), with its disks moved first to a shared storage repository (sr_name) so the
destination host can see them.

Run it::

    live_migrate("https://xenserver", "root", password, "web-01", "Shared NFS")
"""

from connection import connect
from helpers import copy_of_guest, destroy_vm_and_disks, move_disks_to_sr, sr_by_name, wait_for_guest_agent


def live_migrate(url, username, password, source_vm, sr_name, new_vm_name="sdk-example-migrate"):
    """Live-migrate a running VM to another host in the pool, with no downtime. Moves a throwaway
    copy of source_vm, a VM with a guest OS and PV drivers: live migration needs the guest's
    cooperation (VM_LACKS_FEATURE without PV drivers).

    Only the VM's memory moves, so the destination host has to see its disks already: a disk on
    local storage refuses with VM_REQUIRES_SR. Put the copy's disks on the shared SR sr_name first."""
    session = connect(url, username, password)
    vm = copy_of_guest(session, source_vm, new_vm_name)
    move_disks_to_sr(session, vm, sr_by_name(session, sr_name, shared=True))
    session.xenapi.VM.start(vm, False, True)
    wait_for_guest_agent(session, vm)

    source_host = session.xenapi.VM.get_resident_on(vm)
    print("VM is running on: %s" % session.xenapi.host.get_name_label(source_host))

    # Pick a different host in the pool to receive the VM.
    dest_host = next(ref for ref in session.xenapi.host.get_all_records()
                     if ref != source_host)

    # Check the destination can boot it, then live-migrate (empty options = default live migration).
    session.xenapi.VM.assert_can_boot_here(vm, dest_host)
    session.xenapi.VM.pool_migrate(vm, dest_host, {})

    print("Migrated to:      %s" % session.xenapi.host.get_name_label(session.xenapi.VM.get_resident_on(vm)))
    print("Still running:    %s" % session.xenapi.VM.get_power_state(vm))

    # Tidy up so the example is repeatable.
    session.xenapi.VM.hard_shutdown(vm)
    destroy_vm_and_disks(session, vm)
    print("OK: live-migrate")
    session.xenapi.session.logout()
