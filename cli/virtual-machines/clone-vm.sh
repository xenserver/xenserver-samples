# Clone a VM.
#
# Make a fast copy-on-write clone of a VM on the same storage repository — distinct from a full copy — the
# quick way to stamp out new VMs from a halted "golden" image.
#
# Run it:
#   ./workflows.sh clone-vm https://xenserver root "$password"

clone_vm() {
    clone=$(xe vm-clone uuid=$(vm_uuid db-01) new-name-label=xe-example-clone)
    echo "Cloned VM: $clone"
    # Tidy up: vm-uninstall destroys the clone and the disks it owns (vm-destroy would leave them).
    xe vm-uninstall uuid=$clone force=true
    echo "OK: clone-vm"
}
