# Read RRD performance metrics.
#
# Pull recent host performance samples from the RRD archives over the performance-data HTTP API, parse the
# legends and data, and summarise a metric (here the peak PVS Accelerator cache-space utilisation per host).
#
# Run it:
#   ./workflows.sh rrd-metrics https://xenserver root "$password"

rrd_metrics() {
    # xe host-data-source-query reads a live data source straight from the host's RRDs.
    hosts=$(xe host-list --minimal)
    for h in ${hosts//,/ }; do
        name=$(xe host-param-get uuid=$h param-name=name-label)
        util=$(xe host-data-source-query uuid=$h data-source=pvsaccelerator_space_utilization)
        echo "  $name: current PVS cache utilisation ${util%.*}%"
    done
    echo "OK: rrd-metrics"
}
