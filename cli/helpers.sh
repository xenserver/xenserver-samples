# Small helpers several workflows share: reading xe's --minimal output, finding objects, waiting for a
# host or the guest agent, tidying up what an example created (sourced by workflows.sh). remote_xe is
# xe run against the pool, with its address and credentials (connection.sh).

# Bash helpers for `--minimal` (comma-separated) output, so no cut/tr/wc/grep processes are spawned:
first_csv()  { echo "${1%%,*}"; }                       # first element of a comma-separated list
count_csv()  { local IFS=,; set -- $1; echo $#; }       # number of elements (0 for empty)
each_csv()   { local IFS=,; set -- $1; printf '%s\n' "$@"; }   # one element per line, for `for`
nth_csv()    { local n=$2 IFS=,; set -- $1; shift $((n - 1)); echo "$1"; }  # Nth element, 1-based
# A set-valued FIELD (vm-param-get param-name=VBDs, allowed-VBD-devices, ...) is printed "a; b; c" - with
# or without --minimal, which only turns a LIST of objects into a comma-separated line. Convert it, so the
# helpers above work on both.
set_to_csv() { echo "${1//; /,}"; }

# The last line of every workflow: "OK: <workflow>", but only when no xe call failed along the way (see xe()
# in connection.sh).
ok() {
    local failed; failed=$(<"$_xe_failures"); rm -f "$_xe_failures"
    if [ -n "$failed" ]; then printf 'FAILED: %s - these xe calls failed:
%s
' "$1" "$failed" >&2; exit 1; fi
    echo "OK: $1"
}

# The pool's default SR: where xe vm-install puts a template's disks when no SR is named.
default_sr() { remote_xe pool-param-get uuid=$(remote_xe pool-list --minimal) param-name=default-SR; }
# The (first) SR with this name, or a message saying there is none.
sr_by_name() {
    local sr
    sr=$(first_csv "$(remote_xe sr-list name-label="$1" --minimal)")
    if [ -z "$sr" ]; then echo "no SR named '$1'" >&2; return 1; fi
    echo "$sr"
}
first_host() { first_csv "$(remote_xe host-list --minimal)"; }
vm_uuid()  { first_csv "$(remote_xe vm-list name-label="$1" --minimal)"; }

# Detach an SR from every host, then forget it. sr-forget refuses an SR that is still attached (SR_HAS_PBD),
# so unplug its PBDs first. Forgetting drops the pool's record of the SR but leaves the data on the storage
# itself.
detach_and_forget_sr() {
    local pbd
    for pbd in $(each_csv "$(remote_xe pbd-list sr-uuid=$1 currently-attached=true --minimal)"); do
        remote_xe pbd-unplug uuid=$pbd
    done
    remote_xe sr-forget uuid=$1
}

# The text content of the first <tag>...</tag> in an XML fragment, using parameter expansion only (no
# xmllint, and no sed/grep process per tag).
xml_tag_text() {
    local xml=$1 tag=$2 rest
    rest=${xml#*<$tag>}
    [ "$rest" != "$xml" ] || return 1
    echo "${rest%%</$tag>*}"
}

# Return the XML a backend sends back on its deliberately-failing discovery probe (args: sm-type, then
# any sr-probe arguments such as host-uuid=/device-config:key=value). Discover iSCSI/HBA LUNs by
# asking with an incomplete device-config on purpose: the backend can't create anything from it yet,
# so it fails with an SR_BACKEND_FAILURE_<n> whose error parameters carry an XML fragment describing
# what it found - the IQNs on offer, then the LUNs behind one of them, or - for HBA - every LUN
# visible at all. A probe that unexpectedly succeeds means the device-config was already complete -
# not the discovery prompt this helper is looking for. Never probe by attempting sr-create instead: on
# real storage a create that succeeds formats the LUN.
probe_for_failure() {
    local sm_type=$1 out line xml=""
    shift
    # Deliberately xe_try: the probe is expected to fail (that's how it reports what it found).
    if out=$(remote_xe_try sr-probe type="$sm_type" "$@" 2>&1); then
        echo "SR.probe for $sm_type succeeded without asking for more information;" \
             "check the target address" >&2
        return 1
    fi
    # xe prints a known error as "Error code: ..." then "Error parameters: a, b, ..." (the Windows xe.exe says
    # "Error params:"): the XML fragment is always the last parameter xapi sends back, so it runs from the
    # first '<' on that line to the end of the output (a real host pretty-prints it over many lines).
    local in_params=""
    while IFS= read -r line; do
        if [ -n "$in_params" ]; then
            xml+=$'\n'"$line"
        else
            case "$line" in
                "Error param"*":"*"<"*) xml="<${line#*<}"; in_params=1 ;;
            esac
        fi
    done <<< "$out"
    if [ -z "$xml" ]; then
        echo "$out" >&2
        return 1
    fi
    echo "$xml"
}

# Wait for a host to come back from a reboot (key "boot_time") or toolstack restart
# ("agent_start_time"): until that other-config entry differs from $before and the host is live. Follows
# HOST_IS_SLAVE-style coordinator redirection (updating the global $host, the same way the top-of-script
# probe and reconnect_after_master_change do) in case the host restarting is the coordinator xe is
# currently talking to.
wait_for_restart() {
    local host_uuid=$1 key=$2 before=$3 timeout=${4:-1800} interval=${5:-10} probe
    local deadline=$((SECONDS + timeout))
    while true; do
        # Deliberately xe_try: the host is down or restarting for some of this wait, and any call can
        # fail while that happens.
        if probe=$(remote_xe_try host-param-get uuid=$host_uuid param-name=other-config param-key=$key 2>&1); then
            if [ "$probe" != "$before" ] && [ "$(host_live "$host_uuid")" = "true" ]; then
                return 0
            fi
        elif [[ $probe =~ (Master|Coordinator)\ IP\ address:\ ([0-9A-Fa-f.:]+) ]]; then
            host=${BASH_REMATCH[2]}
        fi
        if [ $SECONDS -gt $deadline ]; then
            echo "host $host_uuid did not come back in time" >&2
            return 1
        fi
        sleep "$interval"
    done
}

# Apply the pool's synced updates ($2 hash, from pool-sync-updates) to one host, then act on whatever
# guidance applying them leaves pending, and return it to service. Shared by apply-update, which
# updates one host, and rolling-pool-update, which updates them all.
#
# host-apply-updates refuses a batch whose mandatory guidance needs an evacuation with
# HOST_EVACUATION_IS_REQUIRED unless the host's resident VMs are moved off first - handle that rather
# than assuming an update batch never asks for one: disable the host, evacuate it, and apply again.
# Stays disabled for the reboot: xapi refuses host-reboot on an enabled host (HOST_NOT_DISABLED), and
# enable_when_booted below returns it to service either way. Modern xapi (>=23.18.0) doesn't reboot a
# host for you: it only records pending-guidances, so only reboot (xe has no remote toolstack-restart
# command, see below) when the applied batch actually asks for it; a reboot returns before it has
# happened, and if this host is the coordinator it takes the connection with it, so wait_for_restart
# notes when it last booted, reboots it, and waits until it reports a newer boot time and is live
# again (following the host to its new coordinator address if needed) before this re-enables it.
# Guidance that targets VMs instead of hosts (for example restarting a VM) is not handled here.
#
# $3 (label, default "") prefixes the two progress lines this prints, e.g. the host's name-label
# followed by ": ".
apply_updates_to_host() {
    local h=$1 hash=$2 label=${3:-} err guidance before_key
    if ! err=$(remote_xe_try host-apply-updates uuid=$h hash=$hash 2>&1); then
        case "$err" in
            *[Ee]vacuat*)
                echo "  ${label}needs evacuating first; evacuating and retrying"
                remote_xe host-disable uuid=$h
                remote_xe host-evacuate uuid=$h
                remote_xe host-apply-updates uuid=$h hash=$hash
                # Stays disabled for the reboot: xapi refuses host-reboot on an enabled host
                # (HOST_NOT_DISABLED), and enable_when_booted below returns it to service either way.
                ;;
            *) echo "$err" >&2; exit 1 ;;
        esac
    fi
    guidance=$(set_to_csv "$(remote_xe host-param-get uuid=$h param-name=pending-guidances)")
    echo "  ${label}applied; pending guidance = [$guidance]"
    case ",$guidance," in
        *,reboot_host,*)
            # The reboot returns before it has happened, and if this host is the coordinator it takes
            # the connection with it - so note when it last booted, reboot it, and wait until it
            # reports a newer boot time and is live again before re-enabling it.
            before_key=$(remote_xe_try host-param-get uuid=$h param-name=other-config param-key=boot_time 2>/dev/null) || true
            remote_xe host-reboot uuid=$h
            wait_for_restart "$h" boot_time "$before_key"
            ;;
        *,restart_toolstack,*) echo "    (restart_toolstack requested; xe has no command for that alone)" ;;
    esac
    # apply-updates disables the host while it works (auto_enable: a restart puts it back) - with no
    # restart to do, nothing re-enables it. Return it to service either way.
    enable_when_booted "$h"
}

# Re-enable a host that has just come back. It reports itself live before xapi on it has finished
# starting, and until then host-enable fails HOST_STILL_BOOTING - so retry that.
enable_when_booted() {
    local h=$1 timeout=600 interval=10 err
    local deadline=$((SECONDS + timeout))
    while true; do
        # Deliberately xe_try: HOST_STILL_BOOTING is the expected failure while this waits.
        if err=$(remote_xe_try host-enable uuid=$h 2>&1); then return 0; fi
        # xe prints the error's message, not its code: HOST_STILL_BOOTING reads "The host toolstack is
        # still initialising".
        case "$err" in
            *STILL_BOOTING*|*"still initialising"*) ;;
            *) echo "$err" >&2; return 1 ;;
        esac
        if [ $SECONDS -gt $deadline ]; then echo "$err" >&2; return 1; fi
        sleep "$interval"
    done
}

# A throwaway VM with a working guest OS: a copy of an existing VM that has one. Suspend, checkpoint,
# live migration and clean shutdown all need the guest's cooperation: on a running VM with no PV drivers
# xapi refuses them up front with VM_LACKS_FEATURE (a VM freshly installed from a template has no OS at
# all). So copy a VM that does have an OS and PV drivers, without disturbing it: snapshot it (fine while
# it runs), then vm-install from the snapshot - a clone-and-provision in one step, straight onto the same
# SR as the snapshot's own disks (vm-install refuses an explicit sr-uuid/sr-name-label when installing
# from a snapshot). The snapshot is only needed for the install, so it goes again straight away.
copy_of_guest() {
    local source_vm_name=$1 new_vm_name=$2 source snapshot vm
    source=$(vm_uuid "$source_vm_name")
    snapshot=$(remote_xe vm-snapshot uuid=$source new-name-label="${new_vm_name}-source")
    vm=$(remote_xe vm-install template-uuid=$snapshot new-name-label="$new_vm_name")
    # Even with force=true, *-uninstall prints the items it destroys on stdout: keep that out of the
    # value this function returns.
    remote_xe snapshot-uninstall snapshot-uuid=$snapshot force=true >/dev/null
    echo "$vm"
}

# Wait, after vm-start, until the guest's PV drivers have reported in, then settle. xapi only offers the
# guest-dependent operations once the guest says it can do them, and allowed-operations is where it says
# so: wait for clean_shutdown to appear there (the same check that refuses it with VM_LACKS_FEATURE
# beforehand). A Linux kernel offers that early in boot, before the agent runs (hot-plug needs the agent,
# and suspend needs its emulated disk unplugged), so wait for PV-drivers-detected too. A booting OS takes a
# while.
#
# Even then the guest may still be booting, and a guest asked to suspend mid-boot (suspend, checkpoint, live
# migration) can fail to freeze a process that is busy starting up: it then abandons the suspend without
# telling the host, which waits until VM_SUSPEND_TIMEOUT. xapi has no "boot finished" signal, so also wait
# for the guest to report an IP address - a sign it has finished booting, when it has a network - but that
# is only best effort: a guest with no network (no NIC, DHCP failure, an isolated network) has still
# booted, so a missing IP address by the deadline is not a failure.
wait_for_guest_agent() {
    local vm=$1 timeout=${2:-300} interval=${3:-2} settle=${4:-30}
    local deadline=$((SECONDS + timeout))
    local pv networks
    while true; do
        case "$(remote_xe vm-param-get uuid=$vm param-name=allowed-operations)" in
            *clean_shutdown*)
                # Deliberately xe_try: the guest metrics this reads are not there yet on every round.
                pv=$(remote_xe_try vm-param-get uuid=$vm param-name=PV-drivers-detected 2>/dev/null) || pv=""
                [ "$pv" = true ] && break ;;
        esac
        if [ $SECONDS -gt $deadline ]; then
            echo "the guest did not finish booting (PV drivers) within ${timeout}s; does" \
                 "the source VM have a guest OS with PV drivers (XenServer VM Tools)?" >&2
            return 1
        fi
        sleep "$interval"
    done
    while true; do
        networks=$(remote_xe_try vm-param-get uuid=$vm param-name=networks 2>/dev/null) || networks=""
        [[ $networks == */ip:* || $networks == */ipv4/* ]] && break
        if [ $SECONDS -gt $deadline ]; then
            echo "  no IP address reported within ${timeout}s; carrying on (the guest has no network address)"
            break
        fi
        sleep "$interval"
    done
    sleep "$settle"
}

# Relocate every one of a (not-yet-started) VM's disks onto the given SR, the same vdi-pool-migrate
# storage-migrate already demonstrates.
move_disks_to_sr() {
    local vm=$1 sr_ref=$2 vbd vdi
    for vbd in $(each_csv "$(set_to_csv "$(remote_xe vm-param-get uuid=$vm param-name=VBDs)")"); do
        [ "$(remote_xe vbd-param-get uuid=$vbd param-name=type)" = "Disk" ] || continue
        vdi=$(remote_xe vbd-param-get uuid=$vbd param-name=vdi-uuid)
        if [ "$(remote_xe vdi-param-get uuid=$vdi param-name=sr-uuid)" != "$sr_ref" ]; then
            remote_xe vdi-pool-migrate uuid=$vdi sr-uuid=$sr_ref
        fi
    done
}

# Introduce the pool's update repository: the release's update stream (update=true, which
# pool-sync-updates needs - otherwise NO_REPOSITORY_ENABLED). A real host checks the URL
# (INVALID_BASE_URL for an unknown domain), so this is the XenServer CDN's, e.g.
# https://repo.ops.xenserver.com/xs9/normal. Echoes the repository's uuid.
introduce_update_repository() {
    local repo_url=$1 source_url=$2
    remote_xe repository-introduce name-label="sdk-example-normal" \
        name-description="SDK example update repository" \
        binary-url="$repo_url/normal" source-url="$source_url/normal" \
        update=true
}

# Stop if High Availability or Workload Balancing is on in the pool ($pool). host-apply-updates refuses
# with HA_IS_ENABLED while HA is on, and the documentation also asks for Workload Balancing to be switched
# off before you start updating - so check both up front and stop rather than disabling either for you;
# turn them back on again once the update is done.
check_ha_and_wlb_off() {
    if [ "$(remote_xe pool-param-get uuid=$pool param-name=ha-enabled)" = "true" ] ||
       [ "$(remote_xe pool-param-get uuid=$pool param-name=wlb-enabled)" = "true" ]; then
        echo "HA and Workload Balancing must both be off before updating the pool; disable them," \
             "run this again, then re-enable them once it finishes" >&2
        exit 1
    fi
}

# Get the pool ready to sync updates from $1 (repo_url): check that HA and Workload Balancing are off
# (check_ha_and_wlb_off), then introduce the update repository and make it the pool's only one, putting
# the pool's own repositories back and forgetting the new one when the script exits, however the rest
# goes.
#
# pool-sync-updates syncs the pool's ENABLED repositories, and repository-introduce doesn't enable
# anything (NO_REPOSITORY_ENABLED otherwise). The "repositories" field is DynamicRO at the API level,
# but xe's generic pool-param-set still writes it - a set reads back "a; b" and is set as "a,b".
# Sets pool, repo and before - not local: the EXIT trap reads them after the workflow has returned.
attach_update_repository() {
    local repo_url=$1 source_url=$2
    pool=$(remote_xe pool-list --minimal)
    check_ha_and_wlb_off
    repo=$(introduce_update_repository "$repo_url" "$source_url")
    before=$(remote_xe pool-param-get uuid=$pool param-name=repositories)
    trap 'remote_xe_try pool-param-set uuid=$pool repositories="${before//; /,}"; remote_xe_try repository-forget uuid=$repo' EXIT
    remote_xe pool-param-set uuid=$pool repositories=$repo
}

# The pending guidance an earlier update left, one "<name>: guidance, ..." line per host (host_guidance_lines)
# or per guest VM - not a template, snapshot or control domain (vm_guidance_lines).
host_guidance_lines() {
    local h g
    for h in $(each_csv "$(remote_xe host-list --minimal)"); do
        g=$(remote_xe host-param-get uuid=$h param-name=pending-guidances)
        [ -z "$g" ] || echo "$(remote_xe host-param-get uuid=$h param-name=name-label): ${g//; /, }"
    done
}
vm_guidance_lines() {
    local vm g
    for vm in $(each_csv "$(remote_xe vm-list is-control-domain=false is-a-template=false is-a-snapshot=false --minimal)"); do
        g=$(remote_xe vm-param-get uuid=$vm param-name=pending-guidances)
        [ -z "$g" ] || echo "$(remote_xe vm-param-get uuid=$vm param-name=name-label): ${g//; /, }"
    done
}

# Stop before updating if a host or VM still has mandatory guidance pending from an earlier update.
# host-apply-updates refuses a host that has some (HOST_PENDING_MANDATORY_GUIDANCES_NOT_EMPTY), part-way
# through the update otherwise: act on it first - restart the host, its toolstack or the VM - and run the
# update again.
check_no_pending_guidance() {
    local pending
    pending=$({ host_guidance_lines; vm_guidance_lines; } | sort | paste -sd';' - | sed 's/;/; /g')
    if [ -n "$pending" ]; then
        echo "an earlier update's guidance is still pending - act on it first: $pending" >&2
        exit 1
    fi
}

# Stop before changing anything if a host's VMs could not all move to another host:
# host-get-vms-which-prevent-evacuation names them (for example a VM with a disk on the host's local
# storage, or a pool with nowhere else to put them). $@: the hosts' uuids.
check_hosts_can_be_evacuated() {
    local h blocking vm names
    for h in "$@"; do
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
}

# The pool's hosts' uuids, coordinator first: the update documentation asks for the coordinator to be
# updated before any other host.
hosts_coordinator_first() {
    local master h
    master=$(remote_xe pool-param-get uuid="$(remote_xe pool-list --minimal)" param-name=master)
    echo "$master"
    for h in $(each_csv "$(remote_xe host-list --minimal)"); do
        [ "$h" = "$master" ] || echo "$h"
    done
}

# Apply the synced updates ($1, the hash) to each host in turn ($2...), keeping the VMs running: disable
# the host so nothing new starts there, evacuate it (live-migrating its VMs to the other hosts), and let
# apply_updates_to_host apply the updates, reboot the host if the update asks for that, and enable it
# again. The VMs stay where evacuation put them.
update_hosts() {
    local hash=$1 h
    shift
    for h in "$@"; do
        echo "Updating $(remote_xe host-param-get uuid=$h param-name=name-label): moving its VMs to the rest of the pool"
        remote_xe host-disable uuid=$h
        remote_xe host-evacuate uuid=$h
        apply_updates_to_host "$h" "$hash"
    done
}

# Print the guidance updating left pending for VMs - restart_vm or restart_device_model, for a VM to start
# using what was updated. Acting on it restarts the VM, which is its owner's call rather than the
# update's, so this only reports it.
report_vm_guidance() {
    local pending
    pending=$(vm_guidance_lines | sort | paste -sd';' - | sed 's/;/; /g')
    echo "VM guidance pending: ${pending:-none}"
}

# The VDI behind a VM's first real disk. CD drives are VBDs too, hence the type filter.
first_disk_vdi() {
    local vm=$1 vbd
    for vbd in $(each_csv "$(remote_xe vbd-list vm-uuid=$vm --minimal)"); do
        if [ "$(remote_xe vbd-param-get uuid=$vbd param-name=type)" = "Disk" ]; then
            remote_xe vbd-param-get uuid=$vbd param-name=vdi-uuid
            return
        fi
    done
}

host_live() { remote_xe_try host-param-get uuid=$1 param-name=host-metrics-live; }

# Bytes as GiB to one decimal place, using shell arithmetic only - there is no floating point here, so
# the fraction is worked out from the remainder.
gib() {
    local bytes=$1 whole tenths
    whole=$((bytes / 1073741824))
    tenths=$(((bytes % 1073741824) * 10 / 1073741824))
    echo "${whole}.${tenths} GiB"
}
