# Rolling pool update.
#
# Apply the CDN's updates across the pool with zero downtime: sync the metadata, then for each host in turn
# disable it, evacuate its VMs to the rest of the pool, apply the updates, reboot, and re-enable it —
# host-by-host orchestration.
#
# Run it:
#   ./workflows.sh rolling-pool-update https://xenserver root "$password"
#
# Optional key=value arguments (default):
#   repo_url (https://repo.ops.xenserver.com/xs9)
#   source_url (https://repo-src.ops.xenserver.com/xs9)

# Needs an enabled update repository the same way apply-update does - introduce the base and update
# repositories and attach both, forget them again afterwards. Modern xapi (>=23.18.0) doesn't reboot a
# host for you: it only records pending guidance, so only reboot (xe has no remote toolstack-restart
# command, see apply-update) when the applied batch actually asks for it.
rolling_pool_update() {
    local repo_url source_url repos repo_list pool before hash guidance before_key
    repo_url=$(param repo_url "https://repo.ops.xenserver.com/xs9")
    source_url=$(param source_url "https://repo-src.ops.xenserver.com/xs9")
    repos=$(introduce_update_repositories "$repo_url" "$source_url")
    repo_list=""
    for r in $repos; do repo_list="${repo_list:+$repo_list,}$r"; done
    # pool-sync-updates syncs the pool's ENABLED repositories, and repository-introduce doesn't enable
    # anything (NO_REPOSITORY_ENABLED otherwise). Remember what was there to put it back afterwards. A
    # set reads back "a; b" and is set as "a,b".
    pool=$(xe pool-list --minimal)
    before=$(xe pool-param-get uuid=$pool param-name=repositories)
    xe pool-param-set uuid=$pool repositories=$repo_list
    hash=$(xe pool-sync-updates)
    echo "Synced updates (hash length ${#hash})"
    # Rolling pattern: disable -> evacuate -> apply -> reboot (only if asked) -> re-enable, one host at a time.
    for h in $(each_csv "$(xe host-list --minimal)"); do
        echo "Updating $(xe host-param-get uuid=$h param-name=name-label):"
        xe host-disable uuid=$h
        xe host-evacuate uuid=$h
        xe host-apply-updates uuid=$h hash=$hash
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
