# Rolling pool update.
#
# Apply the CDN's updates to every host in the pool without stopping its VMs: one host at a time,
# coordinator first, move the host's VMs to the rest of the pool, apply the updates, restart it if the
# update asks for that, and return it to service.
#
# Run it:
#   ./workflows.sh rolling-pool-update https://xenserver root "$password"
#
# Optional key=value arguments (default):
#   repo_url (https://repo.ops.xenserver.com/xs9)
#   source_url (https://repo-src.ops.xenserver.com/xs9)

# Check first, before changing anything, that the update can go through: no host or VM may still have
# mandatory guidance pending from an earlier update, and every host must be able to empty
# (check_no_pending_guidance, check_hosts_can_be_evacuated). Then sync, and let update_hosts update each
# host in turn: disable it, evacuate it, apply the updates, reboot it if the update asks for that (xe has
# no remote toolstack-restart command, see helpers.sh), and enable it again. Finally report the guidance
# left for VMs, such as restarting one to pick the update up - that is the VM owner's call.
# attach_update_repository checks that HA and Workload Balancing are off and attaches a throwaway update
# repository, which pool-sync-updates needs; it is forgotten again afterwards.
rolling_pool_update() {
    local hosts hash
    hosts=$(hosts_coordinator_first)
    check_no_pending_guidance
    check_hosts_can_be_evacuated $hosts
    attach_update_repository "$(param repo_url "https://repo.ops.xenserver.com/xs9")" \
        "$(param source_url "https://repo-src.ops.xenserver.com/xs9")"

    hash=$(remote_xe pool-sync-updates)
    echo "Synced updates (hash length ${#hash})"
    update_hosts "$hash" $hosts
    report_vm_guidance
    ok rolling-pool-update
}
