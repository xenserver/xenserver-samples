# Create a VM (full workflow).
#
# Create a VM end to end: pick a template, name the VM, choose an installation source and a home server, set
# CPU & memory, add a disk on a storage repository, attach a network interface and start it — the full
# sequence, rather than a single clone call.
#
# Run it:
#   ./workflows.sh new-vm-wizard https://xenserver root "$password"
#
# Optional key=value arguments (default):
#   template_name (Rocky Linux 8)

new_vm_wizard() {
    local template=$(param template_name "Rocky Linux 8")
    vm=$(xe vm-install template="$template" new-name-label=xe-wizard-vm sr-uuid=$(shared_sr))
    xe vm-param-set uuid=$vm VCPUs-max=2 VCPUs-at-startup=2
    xe vm-memory-limits-set uuid=$vm static-min=512MiB static-max=2GiB dynamic-min=2GiB dynamic-max=2GiB
    vdi=$(xe vdi-create sr-uuid=$(shared_sr) name-label="xe-wizard disk" virtual-size=24GiB type=user)
    xe vbd-create vm-uuid=$vm vdi-uuid=$vdi device=1 type=Disk mode=RW >/dev/null
    xe vif-create vm-uuid=$vm network-uuid=$(first_csv "$(xe network-list --minimal)") device=0 >/dev/null
    xe vm-start uuid=$vm
    echo "power-state: $(xe vm-param-get uuid=$vm param-name=power-state)"
    echo "vCPUs:       $(xe vm-param-get uuid=$vm param-name=VCPUs-max)"
    # Tidy up so the example is repeatable: stop the VM, then vm-uninstall destroys it and the disks it
    # owns (vm-destroy would leave the disks behind). It owns only the template's disks - vm-install marks
    # those (VBD other-config:owner) - not one added with a plain vbd-create, so destroy that one too.
    xe vm-shutdown uuid=$vm force=true
    xe vm-uninstall uuid=$vm force=true
    xe vdi-destroy uuid=$vdi
    echo "OK: new-vm-wizard"
}
