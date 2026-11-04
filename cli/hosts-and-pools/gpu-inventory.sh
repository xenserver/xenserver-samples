# GPU inventory.
#
# Enumerate the pool's GPU groups, their physical GPUs and the vGPU types each offers.
#
# Run it:
#   ./workflows.sh gpu-inventory https://xenserver root "$password"

gpu_inventory() {
    echo "GPU groups:"
    groups=$(xe gpu-group-list --minimal)
    for g in ${groups//,/ }; do
        vtypes=$(set_to_csv "$(xe gpu-group-param-get uuid=$g param-name=supported-VGPU-types)")
        models=""
        for t in ${vtypes//,/ }; do models="$models $(xe vgpu-type-param-get uuid=$t param-name=model-name)"; done
        echo "  - $(xe gpu-group-param-get uuid=$g param-name=name-label): vGPU types:$models"
    done

    # How the pool spreads vGPUs across the physical GPUs in a group: depth-first packs each pGPU
    # full before using the next, breadth-first spreads them out.
    group=$(first_csv "$groups")
    before=$(xe gpu-group-param-get uuid=$group param-name=allocation-algorithm)
    xe gpu-group-param-set uuid=$group allocation-algorithm=breadth-first
    echo "Allocation:      $before -> $(xe gpu-group-param-get uuid=$group param-name=allocation-algorithm)"
    xe gpu-group-param-set uuid=$group allocation-algorithm=$before
    echo "OK: gpu-inventory"
}
