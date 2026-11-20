"""Enter & exit maintenance mode.

Put a host into maintenance mode: disable it so it accepts no new VMs, evacuate its running guests
to another host in the pool, then re-enable it. A throwaway copy of a VM with a guest OS and PV
drivers (source_vm), with its disks on a shared storage repository (sr_name), gives evacuation
something to move.

Run it::

    host_maintenance("https://xenserver", "root", password, "web-01", "Shared NFS")
"""

from connection import connect
from helpers import copy_of_guest, destroy_vm_and_disks, move_disks_to_sr, sr_by_name, wait_for_guest_agent


def host_maintenance(url, username, password, source_vm, sr_name, new_vm_name="sdk-example-maint"):
    """Disable a host, evacuate its running guests to another host, then re-enable it. Pins a
    throwaway copy of source_vm to the host so evacuation has work to do. Evacuation live-migrates
    the guest, which needs its cooperation (VM_LACKS_FEATURE without PV drivers), so source_vm must
    have a guest OS with PV drivers.

    Evacuation needs somewhere else in the pool that can actually see the VM's disk - a VM whose
    only disk is on local (non-shared) storage can't be evacuated at all (VM_REQUIRES_SR), and a
    pool's installation-time default SR is commonly local storage. Put the pinned VM's disk on a
    shared SR explicitly rather than trusting whatever the pool default happens to be."""
    session = connect(url, username, password)
    # Choose a host that is not the pool coordinator, so the coordinator can receive its guests.
    master = list(session.xenapi.pool.get_all_records().values())[0]["master"]
    host_ref = next(ref for ref in session.xenapi.host.get_all_records() if ref != master)
    print("Maintenance host: %s" % session.xenapi.host.get_name_label(host_ref))

    # Pin a running VM to that host so evacuation has something to move.
    vm = copy_of_guest(session, source_vm, new_vm_name)
    move_disks_to_sr(session, vm, sr_by_name(session, sr_name, shared=True))
    session.xenapi.VM.set_affinity(vm, host_ref)
    session.xenapi.VM.start(vm, False, True)
    wait_for_guest_agent(session, vm)
    print("Guest resident on:%s" % session.xenapi.host.get_name_label(session.xenapi.VM.get_resident_on(vm)))

    # Enter maintenance mode: disable the host, then evacuate its guests.
    session.xenapi.host.disable(host_ref)
    print("After disable:    host.enabled = %s" % session.xenapi.host.get_enabled(host_ref))
    session.xenapi.host.evacuate(host_ref)
    print("After evacuate:   guest now on %s"
          % session.xenapi.host.get_name_label(session.xenapi.VM.get_resident_on(vm)))

    # Exit maintenance mode.
    session.xenapi.host.enable(host_ref)
    print("After enable:     host.enabled = %s" % session.xenapi.host.get_enabled(host_ref))

    # Tidy up so the example is repeatable.
    session.xenapi.VM.hard_shutdown(vm)
    destroy_vm_and_disks(session, vm)
    print("OK: host-maintenance")
    session.xenapi.session.logout()
