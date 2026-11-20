# Configure dynamic memory.
#
# Give a VM a dynamic memory range so the host can reclaim memory from it under pressure, and see the ordering
# rule the four bounds must obey enforced.
#
# Run it:
#   ./workflows.sh configure-dynamic-memory https://xenserver root "$password"

configure_dynamic_memory() {
    vm=$(nth_csv "$(remote_xe vm-list power-state=halted --minimal)" 1)
    static_min=$(remote_xe vm-param-get uuid=$vm param-name=memory-static-min)
    static_max=$(remote_xe vm-param-get uuid=$vm param-name=memory-static-max)
    dyn_min=$(remote_xe vm-param-get uuid=$vm param-name=memory-dynamic-min)
    dyn_max=$(remote_xe vm-param-get uuid=$vm param-name=memory-dynamic-max)
    echo "$(remote_xe vm-param-get uuid=$vm param-name=name-label): static $(gib $static_min)-$(gib $static_max), dynamic $(gib $dyn_min)-$(gib $dyn_max)"

    # Room to balloon - within the documented limit: the dynamic minimum must be at least 75% of the
    # static maximum for every supported guest (lower can make it unstable), and never below the static
    # floor, which is the least the guest can boot in.
    floor=$((static_max * 3 / 4))
    [ "$floor" -lt "$static_min" ] && floor=$static_min
    remote_xe vm-memory-dynamic-range-set uuid=$vm min=$floor max=$static_max
    echo "  dynamic range now $(gib $(remote_xe vm-param-get uuid=$vm param-name=memory-dynamic-min))-$(gib $(remote_xe vm-param-get uuid=$vm param-name=memory-dynamic-max))"

    # The ordering is enforced, not advisory: a range wider than the static bounds is refused rather than
    # quietly clamped. Deliberately xe_try: this call is expected to fail, and xe's own explanation of
    # why is worth showing rather than swallowing.
    if err=$(remote_xe_try vm-memory-dynamic-range-set uuid=$vm min=$floor max=$((static_max * 2)) 2>&1); then
        echo "  ERROR: an out-of-range maximum was accepted"
    else
        echo "  refused a dynamic_max above static_max: $err"
    fi

    remote_xe vm-memory-dynamic-range-set uuid=$vm min=$dyn_min max=$dyn_max
    ok configure-dynamic-memory
}
