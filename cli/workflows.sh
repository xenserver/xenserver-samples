#!/usr/bin/env bash
# XenServer CLI (xe) - real-world workflow examples.
#
# Each example performs a common pool-management task entirely through the `xe` command line interface.
# `xe` runs the command server-side over XAPI's thin-CLI protocol, so these are exactly the commands you
# would type against a real host. Objects are addressed by UUID (captured with `--minimal`), and commands
# take `name=value` arguments (with `device-config:key=value` for nested maps).
#
# Usage:
#   ./workflows.sh <workflow> <url> <username> <password> [key=value ...]
#     <workflow>  connect-inventory | create-vm | vm-lifecycle | ... (see the dispatcher for the full list)
#     <url>       e.g. https://xenserver  (see the note on ports below)
#
# Most workflows need only the connection details and run against the dispatcher's built-in
# placeholder defaults below. A few need environment-specific values to do anything real - an iSCSI
# target address, an AD domain, the replica LUN to fail over to - and take them as extra key=value
# arguments after the password, overriding that workflow's default for the named parameter (e.g.
# `create-iscsi-sr <url> <user> <pw> target=192.0.2.30`). cross-pool-copy-vm keeps its own positional
# form instead (<src> <user> <pw> <destUrl> [<destUser> <destPassword> [<vmName>]]).
set -e

# Under Git Bash/MSYS, an argument that looks like a Unix path (e.g. serverpath=/export/vol1) gets
# rewritten to a Windows path before xe sees it. These are all *remote* paths (NFS exports, folders),
# never local files, so disable that conversion for the whole script.
export MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*'

workflow="$1"; url="$2"; user="$3"; pass="$4"
if [ "$workflow" = "cross-pool-copy-vm" ]; then   # only cross-pool-copy-vm takes these
    desturl="$5"; destuser="${6:-$user}"; destpass="${7:-$pass}"; copy_vm="${8:-db-01}"; shift $#
else shift 4; fi

# Every remaining argument is a key=value override of that workflow's placeholder defaults, as in the
# other languages' dispatchers. `param` reads one back, falling through to the caller's default when it
# wasn't supplied on the command line.
declare -A params
for _arg in "$@"; do
    case "$_arg" in
        *=*) params[${_arg%%=*}]=${_arg#*=} ;;
        *) echo "extra arguments must be key=value (got '$_arg')" >&2; exit 2 ;;
    esac
done
param() {
    local key=$1 default=$2
    if [ "${params[$key]+set}" ]; then echo "${params[$key]}"; else echo "$default"; fi
}

# Load the connection, the shared helpers and every workflow (one file each, in a folder per area).
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
source "$here/connection.sh"
source "$here/helpers.sh"
for _file in "$here"/*/*.sh; do source "$_file"; done

case "$workflow" in
    connect-inventory)    connect_inventory ;;
    create-vm)            create_vm ;;
    vm-lifecycle)         vm_lifecycle ;;
    manage-vm-disks)      manage_vm_disks ;;
    dismiss-alerts)       dismiss_alerts ;;
    host-power-on)        host_power_on ;;
    rotate-pool-secret)   rotate_pool_secret ;;
    change-root-password) change_root_password ;;
    manage-certificates)  manage_certificates ;;
    snapshot-schedule)    snapshot_schedule ;;
    manage-vm-groups)     manage_vm_groups ;;
    snapshot-revert)      snapshot_revert ;;
    create-nfs-sr)        create_nfs_sr ;;
    create-network)       create_network ;;
    edit-vm-properties)   edit_vm_properties ;;
    events)               events ;;
    new-vm-wizard)        new_vm_wizard ;;
    live-migrate)         live_migrate ;;
    host-maintenance)     host_maintenance ;;
    configure-ha)         configure_ha ;;
    copy-vm)              copy_vm ;;
    create-vm-with-vgpu)  create_vm_with_vgpu ;;
    tags-and-folders)     tags_and_folders ;;
    configure-updates)    configure_updates ;;
    configure-offline-updates) configure_offline_updates ;;
    clone-vm)             clone_vm ;;
    delete-vm)            delete_vm ;;
    storage-migrate)      storage_migrate ;;
    apply-update)         apply_update ;;
    checkpoint-vm)        checkpoint_vm ;;
    attach-disk)          attach_disk ;;
    wait-for-task)        wait_for_task ;;
    error-handling)       error_handling ;;
    trace-api-calls)      trace_api_calls ;;
    list-templates)       list_templates ;;
    custom-fields)        custom_fields ;;
    gpu-inventory)        gpu_inventory ;;
    read-metrics)         read_metrics ;;
    rename-object)        rename_object ;;
    vm-boot-config)       vm_boot_config ;;
    host-info)            host_info ;;
    list-roles)           list_roles ;;
    pool-properties)      pool_properties ;;
    sr-usage)             sr_usage ;;
    manage-vif)           manage_vif ;;
    list-networks)        list_networks ;;
    vbd-inventory)        vbd_inventory ;;
    pool-tags)            pool_tags ;;
    convert-to-template)  convert_to_template ;;
    find-by-uuid)         find_by_uuid ;;
    rolling-pool-update)  rolling_pool_update ;;
    cross-pool-copy-vm)   cross_pool_copy_vm ;;
    pvs-accelerator)      pvs_accelerator ;;
    configure-pvs-accelerator) configure_pvs_accelerator ;;
    manage-ssh-access)    manage_ssh_access ;;
    manage-vtpm)          manage_vtpm ;;
    export-import-vm)     export_import_vm ;;
    configure-dynamic-memory) configure_dynamic_memory ;;
    manage-vm-media)      manage_vm_media ;;
    backup-host-config)   backup_host_config ;;
    manage-sr-lifecycle)  manage_sr_lifecycle ;;
    reconnect-sr-storage) reconnect_sr_storage ;;
    export-import-vdi)    export_import_vdi ;;
    set-default-sr)       set_default_sr ;;
    server-status-report) server_status_report ;;
    configure-disaster-recovery) configure_disaster_recovery ;;
    disaster-recovery-failover) disaster_recovery_failover ;;
    manage-secureboot-certificates) manage_secureboot_certificates ;;
    restart-host)         restart_host ;;
    manage-crash-dumps)   manage_crash_dumps ;;
    vm-from-snapshot)     vm_from_snapshot ;;
    attach-existing-disk) attach_existing_disk ;;
    changed-block-tracking) changed_block_tracking ;;
    control-domain-memory) control_domain_memory ;;
    rrd-metrics)          rrd_metrics ;;
    reclaim-space)        reclaim_space ;;
    vm-ip-address)        vm_ip_address ;;
    manage-ad-users)      manage_ad_users ;;
    create-iscsi-sr)      create_iscsi_sr ;;
    create-smb-sr)        create_smb_sr ;;
    create-hba-sr)        create_hba_sr ;;
    create-iso-sr)        create_iso_sr ;;
    configure-nrpe)       configure_nrpe ;;
    configure-snmp)       configure_snmp ;;
    configure-clustering) configure_clustering ;;
    manage-pool-membership) manage_pool_membership ;;
    create-bond) create_bond ;;
    manage-vapp)          manage_vapp ;;
    attach-usb-device)    attach_usb_device ;;
    wlb-recommendations)  wlb_recommendations ;;
    configure-pool-options)    configure_pool_options ;;
    configure-console-access)  configure_console_access ;;
    configure-host-storage)    configure_host_storage ;;
    configure-syslog)          configure_syslog ;;
    manage-driver-variants)    manage_driver_variants ;;
    *) echo "unknown workflow: $workflow" >&2; exit 2 ;;
esac
