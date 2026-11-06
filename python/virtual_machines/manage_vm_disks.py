"""Manage VM disks.

Deactivate a running VM's disk, resize it, reactivate it.
"""

from connection import connect
from helpers import copy_of_guest, destroy_vm_and_disks, sr_by_name, wait_for_guest_agent


def manage_vm_disks(url, username, password, source_vm, sr_name, new_vm_name="sdk-example-vm-disks"):
    """Deactivate a data disk, resize it, and reactivate it.

    Not the VM's root/boot disk: a real VM's system disk is unpluggable=false (only a template's
    non-system disks default to unpluggable), so VBD.unplug on it fails on a real host with
    VBD_NOT_UNPLUGGABLE - and the VM has to be running in the first place, or unplug fails with
    VM_BAD_POWER_STATE. Work on a data disk this example adds to its own throwaway VM instead, and
    tidy up afterwards so the example is repeatable. No shrink: real SR backends refuse one
    outright (SR_BACKEND_FAILURE_79), so this only ever grows.

    Plugging and unplugging a disk on a running VM needs the guest's PV drivers
    (VM_MISSING_PV_DRIVERS otherwise), so the VM is a throwaway copy of source_vm, a VM with a
    guest OS and PV drivers."""
    GIB = 1024 * 1024 * 1024
    session = connect(url, username, password)
    vm_ref = copy_of_guest(session, source_vm, new_vm_name)
    session.xenapi.VM.start(vm_ref, False, True)
    wait_for_guest_agent(session, vm_ref)

    sr_ref = sr_by_name(session, sr_name)
    vdi_ref = session.xenapi.VDI.create({
        "name_label": "sdk-example-data-disk", "SR": sr_ref, "virtual_size": str(4 * GIB),
        "type": "user", "sharable": False, "read_only": False, "other_config": {},
    })
    vbd_ref = session.xenapi.VBD.create({
        "VM": vm_ref, "VDI": vdi_ref,
        "userdevice": session.xenapi.VM.get_allowed_VBD_devices(vm_ref)[0],
        "bootable": False,
        "mode": "RW", "type": "Disk", "empty": False, "other_config": {},
        "qos_algorithm_type": "", "qos_algorithm_params": {},
    })
    session.xenapi.VBD.plug(vbd_ref)
    print("Disk attached:  %s" % session.xenapi.VBD.get_currently_attached(vbd_ref))

    # Deactivate = VBD.unplug. The disk stays with the VM; it is just no longer live.
    session.xenapi.VBD.unplug(vbd_ref)
    print("After unplug:   %s" % session.xenapi.VBD.get_currently_attached(vbd_ref))

    size = int(session.xenapi.VDI.get_virtual_size(vdi_ref))
    session.xenapi.VDI.resize(vdi_ref, str(size * 2))
    print("Resized:        %d -> %s bytes" % (size, session.xenapi.VDI.get_virtual_size(vdi_ref)))

    session.xenapi.VBD.plug(vbd_ref)
    print("After plug:     %s" % session.xenapi.VBD.get_currently_attached(vbd_ref))

    # Growing a disk that is attached and live is a DIFFERENT call, not a flag on the same one:
    # resize_online tells the storage layer the guest is using the disk while it grows. Only some
    # storage drivers can (none of a stock XenServer 9's do), and the rest refuse with
    # SR_OPERATION_NOT_SUPPORTED - so ask the SR's driver (its SM record's features) first.
    sr_type = session.xenapi.SR.get_type(sr_ref)
    features = next((r["features"] for r in session.xenapi.SM.get_all_records().values()
                     if r["type"] == sr_type), {})
    if "VDI_RESIZE_ONLINE" in features:
        grown = int(session.xenapi.VDI.get_virtual_size(vdi_ref)) + GIB
        session.xenapi.VDI.resize_online(vdi_ref, str(grown))
        print("Grown online:   %s bytes" % session.xenapi.VDI.get_virtual_size(vdi_ref))
    else:
        print("Grown online:   not supported by %s storage; unplug, resize, plug as above" % sr_type)

    session.xenapi.VM.hard_shutdown(vm_ref)
    destroy_vm_and_disks(session, vm_ref)
    print("OK: manage-vm-disks")
    session.xenapi.session.logout()
