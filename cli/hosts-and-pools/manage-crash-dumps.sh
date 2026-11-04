# Clear a host's crash dumps.
#
# Find the crash dumps a host kept after a failure, report how big and how old they are, then delete them to
# free the space.
#
# Run it:
#   ./workflows.sh manage-crash-dumps https://xenserver root "$password"

manage_crash_dumps() {
    # A host that crashes writes a dump to its local disk and keeps it. They are large and nothing cleans
    # them up, so clearing them once support has what it needs is ordinary housekeeping. They belong to
    # the host that wrote them, so clear them a host at a time.
    target=""
    for h in $(each_csv "$(xe host-list --minimal)"); do
        if [ -n "$(xe host-crashdump-list host-uuid=$h --minimal)" ]; then target=$h; break; fi
    done
    if [ -z "$target" ]; then
        echo "No crash dumps in this pool - nothing to clear."
        echo "OK: manage-crash-dumps"
        return
    fi

    dumps=$(xe host-crashdump-list host-uuid=$target --minimal)
    echo "$(xe host-param-get uuid=$target param-name=name-label) has $(count_csv "$dumps") crash dump(s)"
    total=0
    for d in $(each_csv "$dumps"); do
        size=$(xe host-crashdump-param-get uuid=$d param-name=size)
        total=$((total + size))
        echo "  $(xe host-crashdump-param-get uuid=$d param-name=timestamp)  $((size / 1048576)) MiB"
    done
    echo "  $((total / 1048576)) MiB in total"

    # Deleting a dump frees the space on the host; the host itself is untouched.
    for d in $(each_csv "$dumps"); do xe host-crashdump-destroy uuid=$d; done
    echo "  cleared:  $(xe host-param-get uuid=$target param-name=name-label) now has $(count_csv "$(xe host-crashdump-list host-uuid=$target --minimal)")"
    echo "OK: manage-crash-dumps"
}
