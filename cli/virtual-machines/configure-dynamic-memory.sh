# Configure dynamic memory.
#
# Give a VM a dynamic memory range so the host can reclaim memory from it under pressure, and see the ordering
# rule the four bounds must obey enforced.
#
# Run it:
#   ./workflows.sh configure-dynamic-memory https://xenserver root "$password"

configure_dynamic_memory() {
    vm=$(nth_csv "$(xe vm-list power-state=halted --minimal)" 1)
    static_min=$(xe vm-param-get uuid=$vm param-name=memory-static-min)
    static_max=$(xe vm-param-get uuid=$vm param-name=memory-static-max)
    dyn_min=$(xe vm-param-get uuid=$vm param-name=memory-dynamic-min)
    dyn_max=$(xe vm-param-get uuid=$vm param-name=memory-dynamic-max)
    echo "$(xe vm-param-get uuid=$vm param-name=name-label): static $(gib $static_min)-$(gib $static_max), dynamic $(gib $dyn_min)-$(gib $dyn_max)"

    # Room to balloon - within the documented limit: the dynamic minimum must be at least 75% of the
    # static maximum for every supported guest (lower can make it unstable), and never below the static
    # floor, which is the least the guest can boot in.
    floor=$((static_max * 3 / 4))
    [ "$floor" -lt "$static_min" ] && floor=$static_min
    xe vm-memory-dynamic-range-set uuid=$vm min=$floor max=$static_max
    echo "  dynamic range now $(gib $(xe vm-param-get uuid=$vm param-name=memory-dynamic-min))-$(gib $(xe vm-param-get uuid=$vm param-name=memory-dynamic-max))"

    # The ordering is enforced, not advisory: a range wider than the static bounds is refused rather than
    # quietly clamped.
    # Both streams: xe prints a XenAPI failure on stdout, so 2>/dev/null alone still shows it.
    if xe vm-memory-dynamic-range-set uuid=$vm min=$floor max=$((static_max * 2)) >/dev/null 2>&1; then
        echo "  ERROR: an out-of-range maximum was accepted"
    else
        echo "  refused a dynamic_max above static_max"
    fi

    xe vm-memory-dynamic-range-set uuid=$vm min=$dyn_min max=$dyn_max
    echo "OK: configure-dynamic-memory"
}

# Bytes as GiB to one decimal place, using shell arithmetic only - there is no floating point here, so
# the fraction is worked out from the remainder.
gib() {
    local bytes=$1 whole tenths
    whole=$((bytes / 1073741824))
    tenths=$(((bytes % 1073741824) * 10 / 1073741824))
    echo "${whole}.${tenths} GiB"
}
