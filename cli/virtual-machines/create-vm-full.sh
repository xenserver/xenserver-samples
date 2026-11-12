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
    local template=$(param template_name "Rocky Linux 8") home_host net sr
    vm=$(xe vm-install template="$template" new-name-label=xe-example-full-vm)
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
    xe vbd-create vm-uuid=$vm vdi-uuid=$vdi device=1 type=Disk mode=RW >/dev/null
    echo "Storage:       24 GiB disk on $(xe sr-param-get uuid=$sr param-name=name-label)"

    net=$(first_csv "$(xe network-list --minimal)")
    xe vif-create vm-uuid=$vm network-uuid=$net device=0 >/dev/null
    echo "Networking:    NIC on $(xe network-param-get uuid=$net param-name=name-label)"

    xe vm-start uuid=$vm
    echo "--- Result ---"
    echo "power-state: $(xe vm-param-get uuid=$vm param-name=power-state)"
    echo "vCPUs:       $(xe vm-param-get uuid=$vm param-name=VCPUs-max)"
    echo "disks:       $(count_csv "$(set_to_csv "$(xe vm-param-get uuid=$vm param-name=VBDs)")"), NICs:" \
         "$(count_csv "$(xe vif-list vm-uuid=$vm --minimal)")"
    # Tidy up so the example is repeatable: stop the VM, then vm-uninstall destroys it and the disks it
    # owns (vm-destroy would leave the disks behind). It owns only the template's disks - vm-install marks
    # those (VBD other-config:owner) - not one added with a plain vbd-create, so destroy that one too.
    xe vm-shutdown uuid=$vm force=true
    xe vm-uninstall uuid=$vm force=true
    xe vdi-destroy uuid=$vdi
    ok create-vm-full
}
