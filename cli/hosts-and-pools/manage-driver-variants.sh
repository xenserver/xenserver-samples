# Manage device driver variants.
#
# Inspect a host's device drivers and choose which variant of one to use, seeing the difference between the
# variant that is selected and the one currently loaded.
#
# Run it:
#   ./workflows.sh manage-driver-variants https://xenserver root "$password"

manage_driver_variants() {
    pool=$(first_csv "$(remote_xe pool-list --minimal)")
    host_uuid=$(remote_xe pool-param-get uuid=$pool param-name=master)
    hname=$(remote_xe host-param-get uuid=$host_uuid param-name=name-label)

    drivers=$(remote_xe hostdriver-list host-uuid=$host_uuid --minimal)
    echo "$hname has $(count_csv "$drivers") driver(s)"

    # Sort by name (one xe call per driver to read it, same as the pairs read below) so the printed
    # order and the selection below agree.
    sorted_drivers=$( (for d in $(each_csv "$drivers"); do
        printf '%s\t%s\n' "$(remote_xe hostdriver-param-get uuid=$d param-name=name)" "$d"
    done) | sort | cut -f2)

    # hostdriver-param-get has no "variants-uuid" field (only "variants", a printable name/version
    # summary) - the actual Driver_variant records behind it are found the normal CLI way, with the
    # generic hostdriver-variant-list filtered on driver-uuid=.
    n=0
    for d in $sorted_drivers; do
        n=$((n + 1)); [ "$n" -gt 3 ] && break
        dname=$(remote_xe hostdriver-param-get uuid=$d param-name=name)
        dtype=$(remote_xe hostdriver-param-get uuid=$d param-name=type)
        nvariants=$(count_csv "$(remote_xe hostdriver-variant-list driver-uuid=$d --minimal)")
        active=$(remote_xe hostdriver-param-get uuid=$d param-name=active-variant)
        printf '  %-14s %-10s %d variant(s), active=%s\n' "$dname" "$dtype" "$nvariants" "${active:-(none)}"
    done

    # Select a variant explicitly. It becomes the selected one immediately; whether it is also active
    # depends on whether the hardware is present and the driver already loaded. hostdriver-select on a
    # no-hardware variant raises HOST_DRIVER_NO_HARDWARE - and a host lists drivers for plenty of devices
    # it doesn't have - so pick a driver for hardware this host actually has, and one of its variants
    # that is usable (field "hw-present", not "hardware-present"): the first (driver, variant) pair,
    # across all drivers sorted by name, whose variant reports present.
    driver="" variant=""
    for d in $sorted_drivers; do
        for v in $(each_csv "$(remote_xe hostdriver-variant-list driver-uuid=$d --minimal)"); do
            if [ "$(remote_xe hostdriver-variant-param-get uuid=$v param-name=hw-present)" = "true" ]; then
                driver=$d; variant=$v; break 2
            fi
        done
    done
    if [ -z "$driver" ]; then
        echo "no driver on $hname has a variant for hardware it has" >&2
        return 1
    fi
    dname=$(remote_xe hostdriver-param-get uuid=$driver param-name=name)
    variant_name=$(remote_xe hostdriver-variant-param-get uuid=$variant param-name=name)
    previous=$(remote_xe hostdriver-param-get uuid=$driver param-name=selected-variant)
    remote_xe hostdriver-select uuid=$driver variant-name="$variant_name"
    selected=$(remote_xe hostdriver-param-get uuid=$driver param-name=selected-variant)
    active=$(remote_xe hostdriver-param-get uuid=$driver param-name=active-variant)
    echo "  $dname: selected ${selected:-(none)}, active ${active:-(none)}"

    # The selection persists and only takes effect at the next reboot, so put it back. xe shows the
    # selected variant by name, which is also what hostdriver-select takes.
    case "$previous" in ""|"<not in database>") previous="" ;; esac
    if [ -n "$previous" ] && [ "$previous" != "$variant_name" ]; then
        remote_xe hostdriver-select uuid=$driver variant-name="$previous"
        echo "  $dname: restored selected $previous"
    fi
    ok manage-driver-variants
}
