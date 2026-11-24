# Update an air-gapped pool from a bundle.
#
# Update a pool with no internet access from an update bundle (.xsbundle) downloaded elsewhere: make a
# bundle repository the pool's update repository, upload the bundle, then apply its updates host by host -
# coordinator first, moving each host's VMs to the rest of the pool - so the VMs keep running throughout.
#
# Run it:
#   ./workflows.sh offline-pool-update https://xenserver root "$password" bundle_path=XS9-update.xsbundle
#
# Optional key=value arguments (default):
#   bundle_path (XS9-update.xsbundle)

# Check first, before changing anything, that the update can go through: HA and Workload Balancing off, no
# host or VM with mandatory guidance still pending from an earlier update, and every host able to empty.
# Then make a repository of the bundle kind the pool's only enabled repository - a pool can have only one
# (introducing a second fails), so use the existing one if there is one. pool-sync-bundle uploads the
# bundle to the coordinator, which unpacks it, checks its signature and syncs its updates; xe waits for that
# to finish. The updates themselves are listed only over HTTP (GET /updates), which xe cannot read, but
# each host's latest-synced-updates-applied says whether it has any to apply ("no") - so update_hosts
# updates just those, as rolling-pool-update does, with the repository's hash. Finally report the guidance
# left for VMs, such as restarting one to pick the update up - that is the VM owner's call.
#
# A pool that stays air-gapped keeps its bundle repository for the next bundle; this example puts the
# pool's previous repositories back afterwards so that it can run again on a test pool.
offline_pool_update() {
    local bundle_path hosts h to_update
    bundle_path=$(param bundle_path "XS9-update.xsbundle")
    pool=$(remote_xe pool-list --minimal)
    hosts=$(hosts_coordinator_first)
    check_ha_and_wlb_off
    check_no_pending_guidance
    check_hosts_can_be_evacuated $hosts

    # Remember the pool's own repositories, to put them back afterwards. A set reads back "a; b".
    # Not local (nor is pool): the EXIT trap below reads them after this function has returned.
    before=$(remote_xe pool-param-get uuid=$pool param-name=repositories)
    existing=$(remote_xe repository-list origin=bundle --minimal)
    if [ -n "$existing" ]; then
        repo=$(first_csv "$existing")
    else
        repo=$(remote_xe repository-introduce-bundle name-label=sdk-example-offline \
            name-description="Updates from uploaded bundles")
    fi
    # Forgetting a repository the pool still has enabled fails: restore the pool's own first, however
    # the rest of this goes.
    trap 'remote_xe_try pool-param-set uuid=$pool repositories="$(set_to_csv "$before")"; [ -n "$existing" ] || remote_xe_try repository-forget uuid=$repo' EXIT
    remote_xe pool-param-set uuid=$pool repositories=$repo
    echo "Pool repositories: $(remote_xe repository-param-get uuid=$repo param-name=name-label)"

    remote_xe pool-sync-bundle filename="$bundle_path"
    echo "Uploaded $(basename "$bundle_path")"
    to_update=""
    for h in $hosts; do
        [ "$(remote_xe host-param-get uuid=$h param-name=latest-synced-updates-applied)" = "no" ] &&
            to_update="$to_update $h"
    done
    echo "Hosts with updates to apply: $(echo $to_update | wc -w)"
    [ -z "$to_update" ] || update_hosts "$(remote_xe repository-param-get uuid=$repo param-name=hash)" $to_update
    report_vm_guidance
    ok offline-pool-update
}
