# Storage repository usage.
#
# Report each storage repository's used and total capacity, and rescan one.
#
# Run it:
#   ./workflows.sh sr-usage https://xenserver root "$password"

sr_usage() {
    echo "Storage:"
    xe sr-list params=name-label,physical-size,physical-utilisation
    # Scan the first SR that has any capacity (the DVD and removable-media SRs have none).
    for sr in $(each_csv "$(xe sr-list --minimal)"); do
        [ "$(xe sr-param-get uuid=$sr param-name=physical-size)" -gt 0 ] && break
    done
    xe sr-scan uuid=$sr
    echo "OK: sr-usage"
}
