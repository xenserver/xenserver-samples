# VM boot configuration.
#
# Set a VM's vCPU counts and boot order, then read them back.
#
# Run it:
#   ./workflows.sh vm-boot-config https://xenserver root "$password"
#
# Optional key=value arguments (default):
#   template_name (Rocky Linux 8)

vm_boot_config() {
    local template=$(param template_name "Rocky Linux 8")
    vm=$(xe vm-install template="$template" new-name-label=xe-example-boot)
    xe vm-param-set uuid=$vm VCPUs-max=4 VCPUs-at-startup=2
    # Boot mode: firmware ("bios"/"uefi") lives in HVM-boot-params; Secure Boot in platform:secureboot.
    # "auto" (not a hard-coded "true") is the xe convention: xapi resolves it against
    # whether the pool actually holds Secure Boot certificates, at vm-start time - a hard "true" would
    # claim Secure Boot is on even on a template that was never set up for it, since platform:secureboot
    # does no validation of its own.
    xe vm-param-set uuid=$vm HVM-boot-params:order=cdn HVM-boot-params:firmware=uefi
    xe vm-param-set uuid=$vm platform:secureboot=auto
    echo "vCPUs: $(xe vm-param-get uuid=$vm param-name=VCPUs-at-startup)/$(xe vm-param-get uuid=$vm param-name=VCPUs-max)"
    echo "Boot order: $(xe vm-param-get uuid=$vm param-name=HVM-boot-params param-key=order)"
    echo "Boot mode: firmware=$(xe vm-param-get uuid=$vm param-name=HVM-boot-params param-key=firmware), secureboot=$(xe vm-param-get uuid=$vm param-name=platform param-key=secureboot) (resolved against pool certificates at boot)"
    # Tidy up so the example is repeatable: vm-uninstall destroys the VM and the disks it owns (vm-destroy
    # would leave the disks behind).
    xe vm-uninstall uuid=$vm force=true
    echo "OK: vm-boot-config"
}
