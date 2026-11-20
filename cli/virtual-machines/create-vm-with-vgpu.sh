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
    # one found - supported-VGPU-types is a set server-side, so its order isn't something to rely on -
    # but picked by the type's model name, the same deterministic rule as the other languages.
    candidates=$(for g in $(each_csv "$(remote_xe gpu-group-list --minimal)"); do
        vtypes=$(set_to_csv "$(remote_xe gpu-group-param-get uuid=$g param-name=supported-VGPU-types)")
        for t in ${vtypes//,/ }; do
            model=$(remote_xe vgpu-type-param-get uuid=$t param-name=model-name)
            [ "$model" = "passthrough" ] && continue
            printf '%s\t%s\t%s\n' "$model" "$g" "$t"
        done
    done | sort)
    [ -n "$candidates" ] || { echo "no GPU group offers a vGPU type (is the GPU vendor's host driver installed?)" >&2; return 1; }
    best=$(printf '%s\n' "$candidates" | head -n1)
    group=$(printf '%s' "$best" | cut -f2)
    type=$(printf '%s' "$best" | cut -f3)
    echo "Using vGPU type: $(remote_xe vgpu-type-param-get uuid=$type param-name=model-name)"          "($(( $(remote_xe vgpu-type-param-get uuid=$type param-name=framebuffer-size) / 1048576 )) MB framebuffer)"
    local template=$(param template_name "Rocky Linux 8")
    # No sr-uuid: the template's disks go to the pool's default SR, as VM.provision does.
    vm=$(remote_xe vm-install template="$template" new-name-label=xe-example-vgpu)
    vgpu=$(remote_xe vgpu-create vm-uuid=$vm gpu-group-uuid=$group vgpu-type-uuid=$type)
    echo "Created vGPU: $vgpu"
    # Read the assignment back.
    vgpus=$(remote_xe vgpu-list vm-uuid=$vm --minimal)
    echo "VM now has $(count_csv "$vgpus") vGPU(s); type = $(remote_xe vgpu-param-get uuid=$(first_csv "$vgpus") param-name=type-model-name)"
    # Tidy up so the example is repeatable: the vGPU, then the VM and the disks it owns.
    remote_xe vgpu-destroy uuid=$vgpu
    remote_xe vm-uninstall uuid=$vm force=true >/dev/null
    echo "Cleaned up the example VM and its vGPU."
    ok create-vm-with-vgpu
}
