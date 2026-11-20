# Manage pool membership.
#
# List the pool's member hosts and which one coordinates it, promote a different host to coordinator, then
# promote the original back.
#
# Run it:
#   ./workflows.sh manage-pool-membership https://xenserver root "$password"

manage_pool_membership() {
    local original other
    original=$(remote_xe pool-list params=master --minimal)
    echo "Coordinator: $(remote_xe host-list uuid="$original" params=name-label --minimal)"
    for h in $(each_csv "$(remote_xe host-list --minimal)"); do
        if [ "$h" = "$original" ]; then
            echo "  member: $(remote_xe host-list uuid="$h" params=name-label --minimal) (coordinator)"
        else
            echo "  member: $(remote_xe host-list uuid="$h" params=name-label --minimal)"
            other=$h
        fi
    done

    # Promote another member. The pool database moves with the role and clients are redirected, so this
    # briefly interrupts management traffic - it does not move any VM. pool-designate-new-master restarts
    # xapi pool-wide, so the connection this script is using does not survive it: reconnect (a bounded
    # wait/retry) before touching the pool again, rather than assuming the next xe call will just work.
    # Names first: once the switch starts, the address this script talks to may already be a supporter.
    local other_name original_name
    other_name=$(remote_xe host-list uuid="$other" params=name-label --minimal)
    original_name=$(remote_xe host-list uuid="$original" params=name-label --minimal)
    designate_new_master "$other"
    echo "Promoting:   $other_name (xapi restarts pool-wide; reconnecting)"
    reconnect_after_master_change "$other"
    echo "Promoted:    $other_name"

    # Put it back. Ejecting a member (pool-eject) is the other half of this surface and is deliberately
    # not shown: it cannot be undone from the pool, because rejoining is initiated by the ejected host.
    designate_new_master "$original"
    echo "Restoring:   $original_name (reconnecting again)"
    reconnect_after_master_change "$original"
    echo "Restored:    $original_name"
    ok manage-pool-membership
}

# pool-designate-new-master, retried while the pool is still settling from a previous change: for a while after
# the new coordinator answers, a call can still fail HANDLE_INVALID on its own task ("You gave an invalid object
# reference"). If the change went through anyway, the pool already names $1 as its coordinator: done.
designate_new_master() {
    local uuid=$1 timeout=300 interval=5 err
    local deadline=$((SECONDS + timeout))
    until err=$(remote_xe_try pool-designate-new-master host-uuid="$uuid" 2>&1); do
        case "$err" in
            *"invalid object reference"*|*HANDLE_INVALID*) ;;
            *) echo "$err" >&2; return 1 ;;
        esac
        if [ "$(remote_xe_try pool-param-get uuid="$(remote_xe_try pool-list --minimal)" param-name=master)" = "$uuid" ]; then
            return 0
        fi
        if [ $SECONDS -ge $deadline ]; then
            echo "$err" >&2
            return 1
        fi
        sleep "$interval"
    done
}

# Wait out a pool-wide xapi restart (pool-designate-new-master) and find the new coordinator's address,
# updating $host - xe does not follow HOST_IS_SLAVE itself (see the probe at the top of this script).
#
# pool-designate-new-master returns BEFORE the change: for a while the old coordinator still answers, and
# still says it is the coordinator, until xapi restarts across the pool. So reconnecting is not enough -
# keep reconnecting until the pool names the new coordinator (by uuid) AND every host is back, enabled and
# live. That can take minutes.
reconnect_after_master_change() {
    local new_master_uuid=$1 timeout=600 interval=5 probe
    local deadline=$((SECONDS + timeout))
    while [ $SECONDS -lt $deadline ]; do
        # Called as an if-condition, so set -e does not end the script when one of its xe calls fails -
        # and while xapi restarts across the pool, any of them can.
        if probe=$(remote_xe_try pool-list --minimal 2>&1) && pool_settled_under "$new_master_uuid" "$probe"; then
            return 0
        fi
        if [[ $probe =~ (Master|Coordinator)\ IP\ address:\ ([0-9A-Fa-f.:]+) ]]; then
            host=${BASH_REMATCH[2]}
        fi
        sleep "$interval"
    done
    echo "the pool did not come back after the master change" >&2
    return 1
}

# True once the pool (uuid $2) names $1 as its coordinator AND every host is back, enabled and live. The
# new coordinator answers before the pool has settled - calls made too soon fail (HANDLE_INVALID on the
# operation's own task) - hence the second half.
pool_settled_under() {
    local master h
    master=$(remote_xe_try pool-param-get uuid="$(first_csv "$2")" param-name=master) || return 1
    [ "$master" = "$1" ] || return 1
    for h in $(each_csv "$(remote_xe_try host-list --minimal)"); do
        [ "$(remote_xe_try host-param-get uuid=$h param-name=enabled)" = "true" ] || return 1
        [ "$(host_live "$h")" = "true" ] || return 1
    done
}
