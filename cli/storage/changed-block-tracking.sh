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
    # those blocks, over NBD. Nothing writes to this disk between the two snapshots taken here, so expect
    # zero changed blocks - that's CBT correctly reporting no work to do, not a failure. Decode the bitmap
    # with base64 -d, dump it one byte per line with od, and count the set bits in bash (no popcount
    # builtin, so shift-and-mask each byte).
    encoded=$(xe vdi-list-changed-blocks vdi-from-uuid=$vdi_from vdi-to-uuid=$vdi_to)
    size=$(xe vdi-param-get uuid=$vdi_to param-name=virtual-size)
    blocks=$((size / 65536))
    changed=0
    for byte in $(printf '%s' "$encoded" | base64 -d | od -An -v -tu1); do
        while [ "$byte" -gt 0 ]; do
            changed=$((changed + (byte & 1)))
            byte=$((byte >> 1))
        done
    done
    if [ "$changed" -gt 0 ]; then
        to_copy=$((changed * 640 / 1024)) total=$((size * 10 / 1024 / 1024))
        echo "  $changed blocks of $blocks changed" \
             "($((to_copy / 10)).$((to_copy % 10)) MiB to copy, not $((total / 10)).$((total % 10)) MiB)"
    else
        echo "  0 blocks of $blocks changed: nothing was written to the disk between the snapshots"
    fi

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
    ok changed-block-tracking
}
