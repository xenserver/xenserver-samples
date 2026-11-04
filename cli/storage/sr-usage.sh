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

    # Read caching keeps recently-read blocks in the host's memory. It is switched off per SR by
    # setting o_direct, which asks the storage layer to bypass the cache entirely.
    # Clear any earlier setting first: adding a key the map already holds is an error, and so is removing
    # one it doesn't, hence the || true.
    xe sr-param-remove uuid=$sr param-name=other-config param-key=o_direct >/dev/null 2>&1 || true
    xe sr-param-add uuid=$sr param-name=other-config o_direct=true
    o_direct=$(xe sr-param-get uuid=$sr param-name=other-config param-key=o_direct)
    echo "  read caching on $(xe sr-param-get uuid=$sr param-name=name-label): $([ "$o_direct" = "true" ] && echo off || echo on)"
    xe sr-param-remove uuid=$sr param-name=other-config param-key=o_direct
    echo "OK: sr-usage"
}
