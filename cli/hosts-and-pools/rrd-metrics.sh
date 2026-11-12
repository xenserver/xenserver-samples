# Read RRD performance metrics.
#
# Read a live performance metric (here the PVS Accelerator cache-space utilisation) off every host.
#
# Run it:
#   ./workflows.sh rrd-metrics https://xenserver root "$password"

rrd_metrics() {
    # xe has no command to pull RRD history the way the other languages' rrd_updates HTTP call does -
    # host-data-source-query only reads a data source's current, live value straight off the host, so
    # this reports that rather than claiming a peak it has no way to compute.
    hosts=$(xe host-list --minimal)
    for h in ${hosts//,/ }; do
        name=$(xe host-param-get uuid=$h param-name=name-label)
        util=$(xe host-data-source-query uuid=$h data-source=pvsaccelerator_space_utilization)
        echo "  $name: current PVS cache utilisation ${util%.*}%"
    done
    ok rrd-metrics
}
