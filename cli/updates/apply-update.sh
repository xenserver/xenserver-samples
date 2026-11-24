# Apply updates from the CDN.
#
# Sync the pool's update metadata from the CDN and apply it to one host - the pool coordinator, unless
# you name another - then act on that host's post-update guidance.
#
# Run it:
#   ./workflows.sh apply-update https://xenserver root "$password"
#
# Optional key=value arguments (default):
#   repo_url (https://repo.ops.xenserver.com/xs9)
#   source_url (https://repo-src.ops.xenserver.com/xs9)
#   host_name (empty: the coordinator)

# The documentation asks for the coordinator to be updated before any other host, so update it first,
# then run this again naming each of the others - or use rolling-pool-update to do the whole pool in one
# go. Before changing anything, check_no_pending_guidance stops if a host or VM still has mandatory
# guidance pending from an earlier update. helpers.sh's attach_update_repository checks that HA and
# Workload Balancing are off and attaches a throwaway update repository, which pool-sync-updates needs;
# it is forgotten again afterwards. apply_updates_to_host does the rest: evacuating the host first if that
# turns out to be needed, acting on its post-update guidance, and returning it to service. Finally report
# the guidance left for VMs, such as restarting one to pick the update up - that is the VM owner's call.
apply_update() {
    local host_name h hash
    host_name=$(param host_name "")
    if [ -n "$host_name" ]; then
        h=$(remote_xe host-list name-label="$host_name" --minimal)
        if [ -z "$h" ] || [ "$h" != "${h%%,*}" ]; then
            echo "expected one host named '$host_name', found $(each_csv "$h" | wc -w)" >&2
            exit 1
        fi
    else
        h=$(remote_xe pool-param-get uuid="$(remote_xe pool-list --minimal)" param-name=master)
    fi
    check_no_pending_guidance
    attach_update_repository "$(param repo_url "https://repo.ops.xenserver.com/xs9")" \
        "$(param source_url "https://repo-src.ops.xenserver.com/xs9")"

    hash=$(remote_xe pool-sync-updates)
    echo "Synced updates (hash length ${#hash})"
    apply_updates_to_host "$h" "$hash" "$(remote_xe host-param-get uuid=$h param-name=name-label): "
    report_vm_guidance
    ok apply-update
}
