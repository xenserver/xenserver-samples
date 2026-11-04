# Small helpers several workflows share: reading xe's --minimal output, finding objects, waiting for a
# host or the guest agent, tidying up what an example created (sourced by workflows.sh).

# Bash helpers for `--minimal` (comma-separated) output, so no cut/tr/wc/grep processes are spawned:
first_csv()  { echo "${1%%,*}"; }                       # first element of a comma-separated list
count_csv()  { local IFS=,; set -- $1; echo $#; }       # number of elements (0 for empty)
each_csv()   { local IFS=,; set -- $1; printf '%s\n' "$@"; }   # one element per line, for `for`
nth_csv()    { local n=$2 IFS=,; set -- $1; shift $((n - 1)); echo "$1"; }  # Nth element, 1-based
# A set-valued FIELD (vm-param-get param-name=VBDs, allowed-VBD-devices, ...) is printed "a; b; c" - with
# or without --minimal, which only turns a LIST of objects into a comma-separated line. Convert it, so the
# helpers above work on both.
set_to_csv() { echo "${1//; /,}"; }

shared_sr() { first_csv "$(xe sr-list name-label="Shared NFS" --minimal)"; }
first_host() { first_csv "$(xe host-list --minimal)"; }
vm_uuid()  { first_csv "$(xe vm-list name-label="$1" --minimal)"; }

# Detach an SR from every host, then forget it: XenCenter's Detach followed by Forget. sr-forget refuses an
# SR that is still attached (SR_HAS_PBD), so unplug its PBDs first. Forgetting drops the pool's record of the
# SR but leaves the data on the storage itself.
detach_and_forget_sr() {
    local pbd
    for pbd in $(each_csv "$(xe pbd-list sr-uuid=$1 currently-attached=true --minimal)"); do
        xe pbd-unplug uuid=$pbd
    done
    xe sr-forget uuid=$1
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
# any sr-probe arguments such as host-uuid=/device-config:key=value). The New SR wizard discovers
# iSCSI/HBA LUNs by asking with an incomplete device-config on purpose: the backend can't create anything
# from it yet, so it fails with an SR_BACKEND_FAILURE_<n> whose error parameters carry an XML fragment
# describing what it found - the IQNs on offer, then the LUNs behind one of them, or - for HBA - every
# LUN visible at all. A probe that unexpectedly succeeds means the device-config was already complete -
# not the discovery prompt this helper is looking for. Never probe by attempting sr-create instead: on
# real storage a create that succeeds formats the LUN.
probe_for_failure() {
    local sm_type=$1 out line xml=""
    shift
    if out=$(xe sr-probe type="$sm_type" "$@" 2>&1); then
        echo "SR.probe for $sm_type succeeded without asking for more information;" \
             "check the target address" >&2
        return 1
    fi
    # xe prints a known error as "Error code: ..." then "Error parameters: a, b, ..." (the Windows xe.exe
    # that ships with XenCenter says "Error params:"): the XML fragment is always the last parameter xapi
    # sends back, so it runs from the first '<' on that line to the end of the output (a real host
    # pretty-prints it over many lines).
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
        if probe=$(xe host-param-get uuid=$host_uuid param-name=other-config param-key=$key 2>&1); then
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

# Re-enable a host that has just come back. It reports itself live before xapi on it has finished
# starting, and until then host-enable fails HOST_STILL_BOOTING - so retry that.
enable_when_booted() {
    local h=$1 timeout=600 interval=10 err
    local deadline=$((SECONDS + timeout))
    while true; do
        if err=$(xe host-enable uuid=$h 2>&1); then return 0; fi
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
    snapshot=$(xe vm-snapshot uuid=$source new-name-label="${new_vm_name}-source")
    vm=$(xe vm-install template-uuid=$snapshot new-name-label="$new_vm_name")
    # Even with force=true, *-uninstall prints the items it destroys on stdout: keep that out of the
    # value this function returns.
    xe snapshot-uninstall snapshot-uuid=$snapshot force=true >/dev/null
    echo "$vm"
}

# Wait, after vm-start, until the guest's PV drivers have reported in. xapi only offers the
# guest-dependent operations once the guest says it can do them, and allowed-operations is where it says
# so: wait for clean_shutdown to appear there (the same check that refuses it with VM_LACKS_FEATURE
# beforehand). A Linux kernel offers that early in boot, before the agent runs (hot-plug needs the agent,
# and suspend needs its emulated disk unplugged), so wait for PV-drivers-detected too. A booting OS takes a
# while.
wait_for_guest_agent() {
    local vm=$1 timeout=${2:-300} interval=${3:-2}
    local deadline=$((SECONDS + timeout))
    while true; do
        case "$(xe vm-param-get uuid=$vm param-name=allowed-operations)" in
            *clean_shutdown*)
                [ "$(xe vm-param-get uuid=$vm param-name=PV-drivers-detected 2>/dev/null)" = true ] && return 0 ;;
        esac
        if [ $SECONDS -gt $deadline ]; then
            echo "the guest's PV drivers did not report in within ${timeout}s; does the source VM have" \
                 "a guest OS with PV drivers (XenServer VM Tools)?" >&2
            return 1
        fi
        sleep "$interval"
    done
}

# Relocate every one of a (not-yet-started) VM's disks onto the given SR, the same vdi-pool-migrate
# storage-migrate already demonstrates.
move_disks_to_sr() {
    local vm=$1 sr_ref=$2 vbd vdi
    for vbd in $(each_csv "$(set_to_csv "$(xe vm-param-get uuid=$vm param-name=VBDs)")"); do
        [ "$(xe vbd-param-get uuid=$vbd param-name=type)" = "Disk" ] || continue
        vdi=$(xe vbd-param-get uuid=$vbd param-name=vdi-uuid)
        if [ "$(xe vdi-param-get uuid=$vdi param-name=sr-uuid)" != "$sr_ref" ]; then
            xe vdi-pool-migrate uuid=$vdi sr-uuid=$sr_ref
        fi
    done
}

# Introduce the pool's update repositories the way XenCenter does: the release's base packages
# (update=false) and its update stream (update=true, which pool-sync-updates needs - otherwise
# NO_REPOSITORY_ENABLED). A real host checks the URLs (INVALID_BASE_URL for an unknown domain), so these
# are the XenServer CDN's, e.g. https://repo.ops.xenserver.com/xs9/{base,normal}. Echoes both repository
# uuids, one per line.
introduce_update_repositories() {
    local repo_url=$1 source_url=$2 stage
    for stage in base normal; do
        xe repository-introduce name-label="sdk-example-$stage" \
            name-description="SDK example $stage repository" \
            binary-url="$repo_url/$stage" source-url="$source_url/$stage" \
            update=$([ "$stage" = base ] && echo false || echo true)
    done
}

# The VDI behind a VM's first real disk. CD drives are VBDs too, hence the type filter.
first_disk_vdi() {
    local vm=$1 vbd
    for vbd in $(each_csv "$(xe vbd-list vm-uuid=$vm --minimal)"); do
        if [ "$(xe vbd-param-get uuid=$vbd param-name=type)" = "Disk" ]; then
            xe vbd-param-get uuid=$vbd param-name=vdi-uuid
            return
        fi
    done
}

host_live() { xe host-param-get uuid=$1 param-name=host-metrics-live; }
