# Apply updates from the CDN.
#
# Sync the pool's update metadata from the CDN and apply it to every host, starting with the pool
# coordinator, then read each host's post-update reboot guidance.
#
# Run it:
#   ./workflows.sh apply-update https://xenserver root "$password"
#
# Optional key=value arguments (default):
#   repo_url (https://repo.ops.xenserver.com/xs9)
#   source_url (https://repo-src.ops.xenserver.com/xs9)

# host-apply-updates refuses with HA_IS_ENABLED while HA is on, and the documentation also asks for
# Workload Balancing to be switched off before you start updating - so check both up front and stop
# rather than disabling either for you; turn them back on again once the update is done.
#
# pool-sync-updates needs at least one repository with update=true enabled (NO_REPOSITORY_ENABLED
# otherwise) - introduce the base and update repositories and attach both, remembering what was there to
# put it back afterwards (the "repositories" field is DynamicRO at the API level, but xe's generic
# pool-param-set still writes it - a set reads back "a; b" and is set as "a,b"), forgetting the throwaway
# ones again afterwards. Applying a batch whose mandatory guidance needs an evacuation fails with
# HOST_EVACUATION_IS_REQUIRED unless the host's resident VMs are moved off first; handle that rather than
# assuming an update batch never asks for one. Guidance that targets VMs instead of hosts (for example
# restarting a VM) is not handled here.
apply_update() {
    local repo_url source_url repos repo_list pool master h ordered before hash err guidance
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
    before=$(xe pool-param-get uuid=$pool param-name=repositories)
    xe pool-param-set uuid=$pool repositories=$repo_list

    hash=$(xe pool-sync-updates)
    echo "Synced updates (hash length ${#hash})"
    # Coordinator first, as the documentation requires.
    master=$(xe pool-param-get uuid=$pool param-name=master)
    ordered=$master
    for h in $(each_csv "$(xe host-list --minimal)"); do
        [ "$h" = "$master" ] || ordered="$ordered $h"
    done
    for h in $ordered; do
        if ! err=$(xe host-apply-updates uuid=$h hash=$hash 2>&1); then
            case "$err" in
                *[Ee]vacuat*)
                    echo "  $(xe host-param-get uuid=$h param-name=name-label): needs evacuating first; evacuating and retrying"
                    xe host-disable uuid=$h
                    xe host-evacuate uuid=$h
                    xe host-apply-updates uuid=$h hash=$hash
                    xe host-enable uuid=$h
                    ;;
                *) echo "$err" >&2; exit 1 ;;
            esac
        fi
        guidance=$(set_to_csv "$(xe host-param-get uuid=$h param-name=pending-guidances)")
        echo "  $(xe host-param-get uuid=$h param-name=name-label): applied; pending guidance = [$guidance]"
        # Modern xapi (>=23.18.0) doesn't reboot a host for you: it only records guidance, so only act
        # when the applied batch actually asked for it. A reboot restarts the toolstack too, so
        # reboot_host (checked first) covers restart_toolstack as well; xe has no separate command to
        # restart just the toolstack, so note it rather than silently doing nothing in that rarer case.
        case ",$guidance," in
            *,reboot_host,*)
                # As in rolling-pool-update: the reboot returns before it has happened, and the
                # coordinator's takes the connection with it - so wait for a newer boot time.
                before_key=$(xe host-param-get uuid=$h param-name=other-config param-key=boot_time 2>/dev/null) || true
                xe host-reboot uuid=$h
                wait_for_restart "$h" boot_time "$before_key"
                ;;
            *,restart_toolstack,*) echo "    (restart_toolstack requested; xe has no command for that alone)" ;;
        esac
        # apply-updates disables the host while it works (auto_enable: a restart puts it back) - with no
        # restart to do, nothing re-enables it. Return it to service either way.
        enable_when_booted "$h"
    done
    xe pool-param-set uuid=$pool repositories="${before//; /,}"
    for r in $repos; do xe repository-forget uuid=$r; done
    echo "OK: apply-update"
}
