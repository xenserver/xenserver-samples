# Back up with changed block tracking.
#
# Walk an incremental backup: turn on changed block tracking, snapshot twice, ask the server which blocks
# differ, then release the older snapshot's data while keeping the change metadata the next incremental needs.
#
# Run it:
#   ./workflows.sh changed-block-tracking https://xenserver root "$password"

changed_block_tracking() {
    vm=""
    for candidate in $(each_csv "$(xe vm-list is-a-template=false is-control-domain=false is-a-snapshot=false --minimal)"); do
        [ -n "$(first_disk_vdi "$candidate")" ] || continue
        vm=$candidate; break
    done
    [ -n "$vm" ] || { echo "no VM with a disk was found" >&2; exit 1; }
    echo "Backing up $(xe vm-param-get uuid=$vm param-name=name-label)"

    # CBT is switched on for the VM's own disk, and every snapshot taken from then on inherits it. It
    # can't be switched on for a snapshot's disk after the fact (OPERATION_NOT_ALLOWED).
    live=$(first_disk_vdi "$vm")
    was_enabled=$(xe vdi-param-get uuid=$live param-name=cbt-enabled)
    [ "$was_enabled" = "true" ] || xe vdi-enable-cbt uuid=$live

    first=$(xe vm-snapshot uuid=$vm new-name-label=cbt-backup-1)
    second=$(xe vm-snapshot uuid=$vm new-name-label=cbt-backup-2)
    vdi_from=$(first_disk_vdi "$first")
    vdi_to=$(first_disk_vdi "$second")

    # One bit per 64 KiB block, base64-encoded; bit N set means block N changed. A real backup reads only
    # those blocks, over NBD. Counting the bits needs a decoder, which bash is not - so report the size
    # of the answer and let the language examples do the arithmetic.
    encoded=$(xe vdi-list-changed-blocks vdi-from-uuid=$vdi_from vdi-to-uuid=$vdi_to)
    size=$(xe vdi-param-get uuid=$vdi_to param-name=virtual-size)
    echo "  bitmap of ${#encoded} base64 chars covers $((size / 65536)) blocks of 64 KiB"

    # Release the older snapshot's blocks but keep its change metadata, so the next incremental can still
    # diff against it. vdi-data-destroy refuses a disk that a VM still uses (VDI_IN_USE), so drop the older
    # snapshot's VM record first (snapshot-destroy leaves its disk), as a backup tool does. The VDI record
    # stays; its type changes.
    xe snapshot-destroy uuid=$first
    xe vdi-data-destroy uuid=$vdi_from
    echo "  older snapshot is now type=$(xe vdi-param-get uuid=$vdi_from param-name=type), still cbt-enabled=$(xe vdi-param-get uuid=$vdi_from param-name=cbt-enabled)"

    # Tidy up: the newer snapshot and its disk, the metadata-only VDI, and CBT on the VM's own disk if this
    # example switched it on.
    xe snapshot-uninstall snapshot-uuid=$second force=true
    xe vdi-destroy uuid=$vdi_from
    [ "$was_enabled" = "true" ] || xe vdi-disable-cbt uuid=$live
    echo "OK: changed-block-tracking"
}
