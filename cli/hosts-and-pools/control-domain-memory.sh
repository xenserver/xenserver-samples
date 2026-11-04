# Change control domain memory.
#
# Read and change a host's control domain (dom0) memory, then put it back. One setter pins the static and
# dynamic bounds together, because dom0 does not balloon.
#
# Run it:
#   ./workflows.sh control-domain-memory https://xenserver root "$password"

control_domain_memory() {
    h=$(nth_csv "$(xe host-list --minimal)" 1)
    # dom0 is a VM like any other, and vm-list includes it: one control domain per host.
    dom0=$(first_csv "$(xe vm-list is-control-domain=true resident-on=$h --minimal)")
    [ -n "$dom0" ] || { echo "the host reports no control domain" >&2; return 1; }
    original=$(xe vm-param-get uuid=$dom0 param-name=memory-dynamic-min)
    echo "$(xe host-param-get uuid=$h param-name=name-label) dom0: $((original / 1024 / 1024 / 1024)) GiB"

    # vm-memory-set, not vm-memory-limits-set: dom0 does not balloon, so one value pins the static and
    # dynamic bounds and the target together. It takes effect at the host's next reboot.
    xe vm-memory-set uuid=$dom0 memory=$((original + 1073741824))
    echo "  now $(( $(xe vm-param-get uuid=$dom0 param-name=memory-dynamic-min) / 1024 / 1024 / 1024 )) GiB (static $(xe vm-param-get uuid=$dom0 param-name=memory-static-min)-$(xe vm-param-get uuid=$dom0 param-name=memory-static-max), dynamic $(xe vm-param-get uuid=$dom0 param-name=memory-dynamic-min)-$(xe vm-param-get uuid=$dom0 param-name=memory-dynamic-max))"

    xe vm-memory-set uuid=$dom0 memory=$original    # leave the pool as we found it
    echo "OK: control-domain-memory"
}
