# Pool properties.
#
# Read the pool name and default storage repository, then rename the pool and restore it.
#
# Run it:
#   ./workflows.sh pool-properties https://xenserver root "$password"

pool_properties() {
    pool=$(xe pool-list --minimal)
    original=$(xe pool-param-get uuid=$pool param-name=name-label)
    echo "Pool: '$original'"
    xe pool-param-set uuid=$pool name-label=xe-pool-renamed
    echo "Renamed to: '$(xe pool-param-get uuid=$pool param-name=name-label)'"
    xe pool-param-set uuid=$pool name-label="$original"
    echo "OK: pool-properties"
}
