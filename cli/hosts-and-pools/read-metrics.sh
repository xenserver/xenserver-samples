# Read host & VM metrics.
#
# Read live host metrics (total/free memory, liveness) and VM metrics (vCPU count, memory).
#
# Run it:
#   ./workflows.sh read-metrics https://xenserver root "$password"

read_metrics() {
    h=$(first_host)
    # On the CLI, a host's and a VM's metrics read as parameters of the host and VM themselves.
    total=$(remote_xe host-param-get uuid=$h param-name=memory-total)
    free=$(remote_xe host-compute-free-memory uuid=$h)
    echo "Host $(remote_xe host-param-get uuid=$h param-name=name-label): $((total / 1048576)) MiB total," \
         "$((free / 1048576)) MiB free, live=$(remote_xe host-param-get uuid=$h param-name=host-metrics-live)"
    vm=$(vm_uuid web-01)
    mem=$(remote_xe vm-param-get uuid=$vm param-name=memory-actual)
    echo "VM web-01: $(remote_xe vm-param-get uuid=$vm param-name=VCPUs-number) vCPU(s), $((mem / 1048576)) MiB"
    ok read-metrics
}
