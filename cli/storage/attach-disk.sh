# Attach a new disk.
#
# Create a fresh virtual disk on a storage repository and attach it to a VM.
#
# Run it:
#   ./workflows.sh attach-disk https://xenserver root "$password"
#
# Optional key=value arguments (default):
#   template_name (Rocky Linux 8)

attach_disk() {
    local template=$(param template_name "Rocky Linux 8")
    vm=$(xe vm-install template="$template" new-name-label=xe-example-attachdisk sr-uuid=$(shared_sr))
    vdi=$(xe vdi-create sr-uuid=$(shared_sr) name-label=xe-example-data-disk virtual-size=8GiB type=user)
    xe vbd-create vm-uuid=$vm vdi-uuid=$vdi device=1 type=Disk mode=RW >/dev/null
    echo "Attached an 8 GiB disk; VM now has $(count_csv "$(set_to_csv "$(xe vm-param-get uuid=$vm param-name=VBDs)")") VBD(s)"
    # Tidy up: vm-uninstall destroys the VM and the disks it OWNS (VBD other-config:owner, which vm-install
    # sets on the template's disks) - not the one just attached, so destroy that too.
    xe vm-uninstall uuid=$vm force=true
    xe vdi-destroy uuid=$vdi
    echo "OK: attach-disk"
}
