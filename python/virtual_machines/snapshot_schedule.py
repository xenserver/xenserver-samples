"""Snapshot schedule.

Create a scheduled-snapshot policy, attach a VM to it, run it on demand and watch the retention
limit prune the oldest snapshot away.

Run it::

    snapshot_schedule("https://xenserver", "root", password, "web-01")
"""

from connection import connect
from helpers import NULL_REF, destroy_vm_and_disks, vm_by_name


def snapshot_schedule(url, username, password, vm_name, schedule_name="sdk-example-schedule"):
    """Create a scheduled-snapshot policy, attach a VM, run it, and watch retention prune."""
    session = connect(url, username, password)
    vm_ref = vm_by_name(session, vm_name)

    # retained_snapshots is the interesting field: the schedule prunes to it every time it runs.
    vmss_ref = session.xenapi.VMSS.create({
        "name_label": schedule_name,
        "name_description": "Scheduled snapshots created by the SDK example",
        "enabled": True,
        "type": "snapshot",
        "frequency": "daily",
        "retained_snapshots": "2",
        "schedule": {"hour": "2", "min": "0"},
    })
    print("Created schedule: %s" % session.xenapi.VMSS.get_uuid(vmss_ref))

    session.xenapi.VM.set_snapshot_schedule(vm_ref, vmss_ref)
    print("Members:          %d" % len(session.xenapi.VMSS.get_VMs(vmss_ref)))

    # Run it three times against a retention of two: the oldest is pruned away. Compare against the
    # snapshots the VM already had, so only the schedule's own are counted (and tidied up below).
    before = set(session.xenapi.VM.get_snapshots(vm_ref))
    for _ in range(3):
        session.xenapi.VMSS.snapshot_now(vmss_ref)
    kept = [s for s in session.xenapi.VM.get_snapshots(vm_ref) if s not in before]
    print("Snapshots kept:   %d (retention 2)" % len(kept))

    # Tidy up: a schedule with VMs still on it cannot be destroyed (VMSS_HAS_VM), so take the VM off it
    # first. Destroying the schedule leaves the snapshots it took, so destroy those too, with their disks.
    session.xenapi.VM.set_snapshot_schedule(vm_ref, NULL_REF)
    session.xenapi.VMSS.destroy(vmss_ref)
    for snapshot in kept:
        destroy_vm_and_disks(session, snapshot)
    print("OK: snapshot-schedule")
    session.xenapi.session.logout()
