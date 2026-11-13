# Pool properties.
#
# Read the pool name and default storage repository, then rename the pool and restore it.
#
# Run it:
#   ./workflows.sh pool-properties https://xenserver root "$password"

pool_properties() {
    pool=$(xe pool-list --minimal)
    original=$(xe pool-param-get uuid=$pool param-name=name-label)
    default_sr_uuid=$(xe pool-param-get uuid=$pool param-name=default-SR)
    echo "Pool: '$original'"
    if [ -z "$default_sr_uuid" ]; then
        echo "Default SR: (none)"
    else
        echo "Default SR: $(xe sr-param-get uuid=$default_sr_uuid param-name=name-label)"
    fi
    xe pool-param-set uuid=$pool name-label=xe-pool-renamed
    echo "Renamed to: '$(xe pool-param-get uuid=$pool param-name=name-label)'"
    xe pool-param-set uuid=$pool name-label="$original"
    ok pool-properties
}
