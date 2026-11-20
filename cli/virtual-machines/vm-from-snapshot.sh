# Create a VM and a template from a snapshot.
#
# Turn a snapshot into a new VM that stands on its own, and into a reusable custom template.
#
# Run it:
#   ./workflows.sh vm-from-snapshot https://xenserver root "$password"

vm_from_snapshot() {
    # A snapshot is a VM record with is-a-snapshot (and is-a-template) set, so xe can install a VM from it
    # like from any template, or clone it into a custom template that stands on its own.
    vm=$(vm_uuid db-01)
    snap=$(remote_xe vm-snapshot uuid=$vm new-name-label=xe-example-source-snapshot)
    echo "Snapshot of db-01 taken"

    # vm-install from the snapshot gives an ordinary VM you can start, as from any template.
    newvm=$(remote_xe vm-install template-uuid=$snap new-name-label=xe-example-vm-from-snapshot)
    echo "  new VM:      $(remote_xe vm-param-get uuid=$newvm param-name=name-label) (is-a-template=$(remote_xe vm-param-get uuid=$newvm param-name=is-a-template))"

    # snapshot-clone gives a template, not another snapshot: a starting point to stamp more VMs from.
    tmpl=$(remote_xe snapshot-clone uuid=$snap new-name-label=xe-example-template-from-snapshot)
    echo "  new template:$(remote_xe template-param-get uuid=$tmpl param-name=name-label) (is-a-template=$(remote_xe template-param-get uuid=$tmpl param-name=is-a-template))"

    # Each made its own disks, and the snapshot has its own snapshot disks; the -uninstall commands destroy
    # them along with the records. Three destroy banners in a row is noisy, so quiet them and report the
    # clean-up as one line instead.
    remote_xe vm-uninstall uuid=$newvm force=true >/dev/null
    remote_xe template-uninstall template-uuid=$tmpl force=true >/dev/null
    remote_xe snapshot-uninstall snapshot-uuid=$snap force=true >/dev/null
    echo "Cleaned up the example VM, template and snapshot."
    ok vm-from-snapshot
}
