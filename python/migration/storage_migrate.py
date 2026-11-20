"""Storage live-migration.

Move a running VM's virtual disk to a different storage repository while the VM keeps running — live
storage migration. Uses a throwaway copy of a VM with a guest OS and PV drivers (source_vm).

Run it::

    storage_migrate("https://xenserver", "root", password, "web-01")
"""

from connection import connect
from helpers import copy_of_guest, destroy_vm_and_disks, disk_vdis, wait_for_guest_agent


def storage_migrate(url, username, password, source_vm, new_vm_name="sdk-example-storagemigrate"):
    """Relocate a running VM's disk to a different SR without stopping it (live storage migration)
    with VDI.pool_migrate.

    Moving a running VM's disk needs the guest's cooperation (VM_LACKS_FEATURE without PV drivers),
    so this works on a throwaway copy of source_vm, a VM with a guest OS and PV drivers. (A halted
    VM's disk moves too, without the guest; what VDI.pool_migrate always needs is a VM to move the
    disk for - a VDI no VBD points at fails VDI_NEEDS_VM_FOR_MIGRATE.)"""
    session = connect(url, username, password)
    vm = copy_of_guest(session, source_vm, new_vm_name)
    session.xenapi.VM.start(vm, False, True)
    wait_for_guest_agent(session, vm)
    vdi = disk_vdis(session, vm)[0]
    source_sr = session.xenapi.VDI.get_SR(vdi)
    print("Disk is on SR: %s" % session.xenapi.SR.get_name_label(source_sr))

    # Pick a different SR that holds disks, that the VM's host can reach (an attached PBD there), and
    # that has room for the disk - a host's local SR is often too small for a VM's disk. Scan a
    # candidate before trusting its free space: the size and utilisation xapi reports are only as
    # fresh as the SR's last scan, and can claim room the storage doesn't have. Live storage
    # migration copies a snapshot of the disk and mirrors the running disk on top of it, so the
    # destination needs room for the disk twice over (a thick-provisioned LVM SR allocates both).
    GIB = 1024 * 1024 * 1024
    host = session.xenapi.VM.get_resident_on(vm)
    size = int(session.xenapi.VDI.get_virtual_size(vdi))
    dest_sr = None
    for ref, r in session.xenapi.SR.get_all_records().items():
        if (ref == source_sr or r["content_type"] == "iso" or r["type"] in ("iso", "udev")
                or not any(session.xenapi.PBD.get_host(pbd) == host
                           and session.xenapi.PBD.get_currently_attached(pbd) for pbd in r["PBDs"])):
            continue
        session.xenapi.SR.scan(ref)
        free = (int(session.xenapi.SR.get_physical_size(ref))
                - int(session.xenapi.SR.get_physical_utilisation(ref)))
        if free >= 2 * size:
            dest_sr = ref
            break
    if dest_sr is None:
        session.xenapi.VM.hard_shutdown(vm)
        destroy_vm_and_disks(session, vm)
        raise RuntimeError("no other SR attached to %s has room for the %d GiB disk twice over"
                            % (session.xenapi.host.get_name_label(host), size // GIB))
    # pool_migrate returns the disk's new VDI: the copy on the destination SR replaces the original.
    vdi = session.xenapi.VDI.pool_migrate(vdi, dest_sr, {})

    now_on = session.xenapi.VDI.get_SR(vdi)
    print("Disk moved to:  %s" % session.xenapi.SR.get_name_label(now_on))

    # Tidy up: the VM and the disks it now owns.
    session.xenapi.VM.hard_shutdown(vm)
    destroy_vm_and_disks(session, vm)
    print("Cleaned up the example VM.")
    print("OK: storage-migrate")
    session.xenapi.session.logout()
