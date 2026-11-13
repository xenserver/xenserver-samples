# Storage repository usage.
#
# Report each storage repository's used and total capacity, and rescan one.
#
# Run it:
#   ./workflows.sh sr-usage https://xenserver root "$password"

sr_usage() {
    echo "Storage:"
    # Built up here rather than piped straight from the loop, so scan_me survives it - every stage of a
    # pipeline runs in its own subshell, and a plain `for ... | sort` would lose it.
    scan_me="" lines=""
    for sr in $(each_csv "$(xe sr-list --minimal)"); do
        size=$(xe sr-param-get uuid=$sr param-name=physical-size)
        [ "$size" -gt 0 ] || continue   # skip ISO/DVD pseudo-SRs, which report no capacity
        [ -n "$scan_me" ] || scan_me=$sr
        util=$(xe sr-param-get uuid=$sr param-name=physical-utilisation)
        name=$(xe sr-param-get uuid=$sr param-name=name-label)
        lines+="$name"$'\t'"  $name: $((util / 1073741824)) / $((size / 1073741824)) GiB used"$'\n'
    done
    printf '%s' "$lines" | sort -t$'\t' -k1,1f | cut -f2-
    # A rescan refreshes an SR's utilisation from its backend.
    xe sr-scan uuid=$scan_me
    ok sr-usage
}
