# Create a VM with a vGPU.
#
# Provision a VM from a template and assign it a virtual GPU: find a GPU group that offers a vGPU type, attach
# it, and read the assignment back.
#
# Run it:
#   ./workflows.sh create-vm-with-vgpu https://xenserver root "$password"
#
# Optional key=value arguments (default):
#   template_name (Rocky Linux 8)

create_vm_with_vgpu() {
    # A GPU group that offers a real (non-passthrough) vGPU type, and that type. Not simply the first
    # group: a host's onboard display adapter is a GPU group too, with no vGPU types at all.
    group="" type=""
    for g in $(each_csv "$(xe gpu-group-list --minimal)"); do
        vtypes=$(set_to_csv "$(xe gpu-group-param-get uuid=$g param-name=supported-VGPU-types)")
        for t in ${vtypes//,/ }; do
            if [ "$(xe vgpu-type-param-get uuid=$t param-name=model-name)" != "passthrough" ]; then
                group=$g; type=$t; break 2
            fi
        done
    done
    [ -n "$type" ] || { echo "no GPU group offers a vGPU type (is the GPU vendor's host driver installed?)" >&2; return 1; }
    local template=$(param template_name "Rocky Linux 8")
    # No sr-uuid: the template's disks go to the pool's default SR, as VM.provision does.
    vm=$(xe vm-install template="$template" new-name-label=xe-example-vgpu)
    vgpu=$(xe vgpu-create vm-uuid=$vm gpu-group-uuid=$group vgpu-type-uuid=$type)
    echo "Created vGPU: $vgpu of type $(xe vgpu-type-param-get uuid=$type param-name=model-name)"
    # Tidy up so the example is repeatable: the vGPU, then the VM and the disks it owns.
    xe vgpu-destroy uuid=$vgpu
    xe vm-uninstall uuid=$vm force=true
    echo "OK: create-vm-with-vgpu"
}
