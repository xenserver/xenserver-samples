# Rolling pool update.
#
# Apply the CDN's updates across the pool with zero downtime: sync the metadata, then for each host in
# turn - coordinator first - apply the updates (evacuating its VMs first only if that turns out to be
# needed), reboot if asked to, and re-enable it — host-by-host orchestration.
#
# Run it:
#   ./workflows.sh rolling-pool-update https://xenserver root "$password"
#
# Optional key=value arguments (default):
#   repo_url (https://repo.ops.xenserver.com/xs9)
#   source_url (https://repo-src.ops.xenserver.com/xs9)

# host-apply-updates refuses with HA_IS_ENABLED while HA is on, and the documentation also asks for
# Workload Balancing to be switched off before you start updating - so check both up front and stop
# rather than disabling either for you; turn them back on again once the update is done.
#
# Needs an enabled update repository the same way apply-update does - introduce the base and update
# repositories and attach both, forget them again afterwards. Modern xapi (>=23.18.0) doesn't reboot a
# host for you: it only records pending guidance, so only reboot (xe has no remote toolstack-restart
# command, see apply-update) when the applied batch actually asks for it, and only evacuate a host first
# if applying without doing so fails with HOST_EVACUATION_IS_REQUIRED - most updates don't need it.
# Guidance that targets VMs instead of hosts (for example restarting a VM) is not handled here.
rolling_pool_update() {
    local repo_url source_url repos repo_list pool master h ordered before hash err guidance before_key
    pool=$(xe pool-list --minimal)
    if [ "$(xe pool-param-get uuid=$pool param-name=ha-enabled)" = "true" ] ||
       [ "$(xe pool-param-get uuid=$pool param-name=wlb-enabled)" = "true" ]; then
        echo "HA and Workload Balancing must both be off before updating the pool; disable them," \
             "run this again, then re-enable them once it finishes" >&2
        exit 1
    fi
    repo_url=$(param repo_url "https://repo.ops.xenserver.com/xs9")
    source_url=$(param source_url "https://repo-src.ops.xenserver.com/xs9")
    repos=$(introduce_update_repositories "$repo_url" "$source_url")
    repo_list=""
    for r in $repos; do repo_list="${repo_list:+$repo_list,}$r"; done
    # pool-sync-updates syncs the pool's ENABLED repositories, and repository-introduce doesn't enable
    # anything (NO_REPOSITORY_ENABLED otherwise). Remember what was there to put it back afterwards. A
    # set reads back "a; b" and is set as "a,b".
    before=$(xe pool-param-get uuid=$pool param-name=repositories)
    xe pool-param-set uuid=$pool repositories=$repo_list
    hash=$(xe pool-sync-updates)
    echo "Synced updates (hash length ${#hash})"
    # Rolling pattern: apply -> evacuate and retry only if that turns out to be needed -> reboot (only if
    # asked) -> re-enable, one host at a time, coordinator first.
    master=$(xe pool-param-get uuid=$pool param-name=master)
    ordered=$master
    for h in $(each_csv "$(xe host-list --minimal)"); do
        [ "$h" = "$master" ] || ordered="$ordered $h"
    done
    for h in $ordered; do
        echo "Updating $(xe host-param-get uuid=$h param-name=name-label):"
        if ! err=$(xe host-apply-updates uuid=$h hash=$hash 2>&1); then
            case "$err" in
                *[Ee]vacuat*)
                    echo "  needs evacuating first; evacuating and retrying"
                    xe host-disable uuid=$h
                    xe host-evacuate uuid=$h
                    xe host-apply-updates uuid=$h hash=$hash
                    xe host-enable uuid=$h
                    ;;
                *) echo "$err" >&2; exit 1 ;;
            esac
        fi
        guidance=$(set_to_csv "$(xe host-param-get uuid=$h param-name=pending-guidances)")
        echo "  applied; pending guidance = $guidance"
        case ",$guidance," in
            *,reboot_host,*)
                # The reboot returns before it has happened, and if this host is the coordinator it takes
                # the connection with it - so note when it last booted, reboot it, and wait until it
                # reports a newer boot time and is live again before re-enabling it.
                before_key=$(xe host-param-get uuid=$h param-name=other-config param-key=boot_time 2>/dev/null) || true
                xe host-reboot uuid=$h
                wait_for_restart "$h" boot_time "$before_key"
                ;;
            *,restart_toolstack,*)
                echo "    (restart_toolstack requested; xe has no command for that alone)"
                ;;
        esac
        enable_when_booted "$h"
    done
    xe pool-param-set uuid=$pool repositories="${before//; /,}"
    for r in $repos; do xe repository-forget uuid=$r; done
    echo "OK: rolling-pool-update"
}
