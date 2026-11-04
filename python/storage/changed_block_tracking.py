"""Back up with changed block tracking.

Walk an incremental backup: turn on changed block tracking, snapshot twice, ask the server which
blocks differ, then release the older snapshot's data while keeping the change metadata the next
incremental needs.
"""

import base64

from connection import connect
from helpers import destroy_vm_and_disks


def changed_block_tracking(url, username, password):
    """Walk an incremental backup: enable CBT, snapshot twice, ask which blocks differ,
    then release the older snapshot's data while keeping the metadata.

    This is the whole point of CBT. Without it an incremental has to read the entire disk
    to find out what moved; with it the server answers directly, and data_destroy means
    the chain of snapshots you diff against costs metadata rather than disk."""
    session = connect(url, username, password)
    x = session.xenapi

    vm = next(ref for ref, v in x.VM.get_all_records().items()
              if not v["is_a_template"] and not v["is_control_domain"]
              and not v["is_a_snapshot"] and v["VBDs"])
    print("Backing up %s" % x.VM.get_name_label(vm))

    # CBT is switched on for the VM's own disk, and every snapshot taken from then on inherits it.
    # It can't be switched on for a snapshot's disk after the fact (OPERATION_NOT_ALLOWED).
    live = first_disk(x, vm)
    was_enabled = x.VDI.get_cbt_enabled(live)
    if not was_enabled:
        x.VDI.enable_cbt(live)

    first = x.VM.snapshot(vm, "cbt-backup-1")
    second = x.VM.snapshot(vm, "cbt-backup-2")
    vdi_from, vdi_to = first_disk(x, first), first_disk(x, second)

    # One bit per 64 KiB block, base64-encoded; bit N set means block N changed. A real backup
    # reads only those blocks, over NBD.
    bitmap = base64.b64decode(x.VDI.list_changed_blocks(vdi_from, vdi_to))
    changed = sum(bin(byte).count("1") for byte in bitmap)
    print("  %d blocks of %d changed (%.1f MiB to copy, not %.1f MiB)"
          % (changed, len(bitmap) * 8, changed * 64 / 1024.0,
             int(x.VDI.get_virtual_size(vdi_to)) / (1024.0 ** 2)))

    # Release the older snapshot's blocks but keep its change metadata, so the next incremental can
    # still diff against it. data_destroy refuses a disk that a VM still uses (VDI_IN_USE), so drop the
    # older snapshot's VM record first, as a backup tool does. The VDI record stays; its type changes.
    x.VM.destroy(first)
    x.VDI.data_destroy(vdi_from)
    print("  older snapshot is now type=%s, still cbt_enabled=%s"
          % (x.VDI.get_type(vdi_from), x.VDI.get_cbt_enabled(vdi_from)))

    # Tidy up: the newer snapshot and its disk, the metadata-only VDI, and CBT on the VM's own disk
    # if this example switched it on.
    destroy_vm_and_disks(session, second)
    x.VDI.destroy(vdi_from)
    if not was_enabled:
        x.VDI.disable_cbt(live)
    print("OK: changed-block-tracking")
    session.logout()


def first_disk(x, vm):
    """The VDI behind a VM's first real disk (a CD drive is a VBD too)."""
    for vbd in x.VM.get_VBDs(vm):
        if x.VBD.get_type(vbd) == "Disk":
            return x.VBD.get_VDI(vbd)
    raise Exception("no disk found")
