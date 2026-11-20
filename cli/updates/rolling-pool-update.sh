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

# Check first that every host can be emptied: host-get-vms-which-prevent-evacuation names the VMs that
# could not move anywhere else (for example a VM with a disk on the host's local storage, or a pool with
# nowhere else to put them) - stop before changing anything if there are any. Then, for each host:
# disable it so nothing new starts there, evacuate it (live-migrating its VMs to the other hosts), and
# let helpers.sh's apply_updates_to_host apply the updates, reboot the host if the update asks for that
# (xe has no remote toolstack-restart command, see helpers.sh), and enable it again. The VMs stay where
# evacuation put them. attach_update_repository checks that HA and Workload Balancing are off and
# attaches a throwaway update repository, which pool-sync-updates needs; it is forgotten again
# afterwards.
rolling_pool_update() {
    local master h hosts blocking vm names hash
    master=$(remote_xe pool-param-get uuid="$(remote_xe pool-list --minimal)" param-name=master)
    hosts=$master
    for h in $(each_csv "$(remote_xe host-list --minimal)"); do
        [ "$h" = "$master" ] || hosts="$hosts $h"
    done
    for h in $hosts; do
        blocking=$(remote_xe host-get-vms-which-prevent-evacuation uuid=$h --minimal)
        if [ -n "$blocking" ]; then
            names=""
            for vm in $(each_csv "$blocking"); do
                names="${names:+$names, }$(remote_xe vm-param-get uuid=$vm param-name=name-label)"
            done
            echo "$(remote_xe host-param-get uuid=$h param-name=name-label) cannot be evacuated:" \
                 "move or shut down $names first" >&2
            exit 1
        fi
    done
    attach_update_repository "$(param repo_url "https://repo.ops.xenserver.com/xs9")" \
        "$(param source_url "https://repo-src.ops.xenserver.com/xs9")"

    hash=$(remote_xe pool-sync-updates)
    echo "Synced updates (hash length ${#hash})"
    for h in $hosts; do
        echo "Updating $(remote_xe host-param-get uuid=$h param-name=name-label): moving its VMs to the rest of the pool"
        remote_xe host-disable uuid=$h
        remote_xe host-evacuate uuid=$h
        apply_updates_to_host "$h" "$hash"
    done
    ok rolling-pool-update
}
