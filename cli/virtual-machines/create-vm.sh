# Create a VM from a template.
#
# Clone one of the built-in templates and provision the clone into a real, installable VM.
#
# Run it:
#   ./workflows.sh create-vm https://xenserver root "$password"
#
# Optional key=value arguments (default):
#   template_name (Rocky Linux 8)

create_vm() {
    local template=$(param template_name "Rocky Linux 8")
    vm=$(xe vm-install template="$template" new-name-label=xe-example-vm)
    echo "Created VM: $vm"
    echo "is-a-template = $(xe vm-param-get uuid=$vm param-name=is-a-template)"
    # Tidy up so the example is repeatable: vm-uninstall destroys the VM and the disks it owns (vm-destroy
    # would leave the disks behind).
    xe vm-uninstall uuid=$vm force=true
    echo "OK: create-vm"
}
