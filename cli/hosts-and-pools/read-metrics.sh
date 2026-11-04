# Read host & VM metrics.
#
# Read live host metrics (total/free memory, liveness) and VM metrics (vCPU count, memory).
#
# Run it:
#   ./workflows.sh read-metrics https://xenserver root "$password"

read_metrics() {
    h=$(first_host)
    # On the CLI, a host's and a VM's metrics read as parameters of the host and VM themselves.
    echo "Host $(xe host-param-get uuid=$h param-name=name-label): free memory $(xe host-compute-free-memory uuid=$h), live=$(xe host-param-get uuid=$h param-name=host-metrics-live)"
    vm=$(vm_uuid web-01)
    echo "VM web-01: $(xe vm-param-get uuid=$vm param-name=VCPUs-number) vCPU(s)"
    echo "OK: read-metrics"
}
