# Create a VM (full workflow).
#
# Create a VM end to end: pick a template, name the VM, choose an installation source and a home server, set
# CPU & memory, add a disk on a storage repository, attach a network interface and start it — the full
# sequence, rather than a single clone call.
#
# Run it:
#   ./workflows.sh create-vm-full https://xenserver root "$password"
#
# Optional key=value arguments (default):
#   template_name (Rocky Linux 8)

create_vm_full() {
    # Not "host": that name is the connection target xe() dials (connection.sh), and shadowing it here
    # would send every xe call below it to an empty address instead.
    local template=$(param template_name "Rocky Linux 8") home_host net sr template_uuid vbd_device
    echo "Template:      $template"
    template_uuid=$(first_csv "$(xe template-list name-label="$template" --minimal)")
    [ -n "$template_uuid" ] || { echo "no template named '$template' was found" >&2; return 1; }
    # vm-clone, not vm-install: vm-install also runs VM.provision, which would create the disk the
    # template's own other-config:disks describes - doubling up with the one this example adds itself
    # below. A clone of a template is itself a template, so mark it an ordinary VM afterward.
    vm=$(xe vm-clone uuid=$template_uuid new-name-label=xe-example-full-vm)
    xe vm-param-set uuid=$vm is-a-template=false
    echo "Created VM:    $vm"
    xe vm-param-set uuid=$vm other-config:install-repository=http://mirror.example.com/rocky/9/os/x86_64
    echo "Install media: network repository"

    # Home server: the host the VM prefers to start on, when more than one in the pool could run it.
    home_host=$(first_host)
    xe vm-param-set uuid=$vm affinity=$home_host
    echo "Home server:   $(xe host-param-get uuid=$home_host param-name=name-label)"

    xe vm-param-set uuid=$vm VCPUs-max=2 VCPUs-at-startup=2
    xe vm-memory-limits-set uuid=$vm static-min=512MiB static-max=2GiB dynamic-min=2GiB dynamic-max=2GiB
    echo "CPU/memory:    2 vCPUs, 2 GiB"

    sr=$(default_sr)
    vdi=$(xe vdi-create sr-uuid=$sr name-label="xe-example-full-vm disk" virtual-size=24GiB type=user)
    vbd_device=$(first_csv "$(set_to_csv "$(xe vm-param-get uuid=$vm param-name=allowed-VBD-devices)")")
    xe vbd-create vm-uuid=$vm vdi-uuid=$vdi device=$vbd_device type=Disk mode=RW >/dev/null
    echo "Storage:       24 GiB disk on $(xe sr-param-get uuid=$sr param-name=name-label)"

    net=$(first_csv "$(xe network-list --minimal)")
    xe vif-create vm-uuid=$vm network-uuid=$net device=0 >/dev/null
    echo "Networking:    NIC on $(xe network-param-get uuid=$net param-name=name-label)"

    xe vm-start uuid=$vm
    echo "--- Result ---"
    echo "power-state: $(xe vm-param-get uuid=$vm param-name=power-state)"
    echo "vCPUs:       $(xe vm-param-get uuid=$vm param-name=VCPUs-max)"
    # type=Disk, in case a future template of this name ships with a CD/DVD drive VBD of its own.
    echo "disks:       $(count_csv "$(xe vbd-list vm-uuid=$vm type=Disk --minimal)"), NICs:" \
         "$(count_csv "$(xe vif-list vm-uuid=$vm --minimal)")"
    # Tidy up so the example is repeatable: stop the VM, then vm-uninstall destroys it (vm-destroy would
    # leave the disk behind). Cloning the template rather than installing from it means nothing here is
    # provisioned, so vm-uninstall owns no disks of its own - destroy the one this example added.
    xe vm-shutdown uuid=$vm force=true
    xe vm-uninstall uuid=$vm force=true
    xe vdi-destroy uuid=$vdi
    echo "Cleaned up the example VM."
    ok create-vm-full
}
