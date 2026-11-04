#!/usr/bin/env python3
"""
XenServer Python SDK - real-world workflow examples.

Each example is a self-contained function that mirrors a task you would perform in
XenCenter, driven entirely through the XenServer Management API (XenAPI). The Python
binding (XenAPI.py) speaks XML-RPC and is included with the SDK.

Each workflow is a module of its own, in a package per area (getting_started/, virtual_machines/,
storage/, ...). Its function takes the connection details (and any object it acts on, looked up by
name) as parameters, opens its own session and logs out when done, so you can copy one into your own
code along with connection.py (and any helper from helpers.py it uses); its module docstring shows the
call. This file is only the command-line dispatcher, which lets one program run any of them.

Usage:
    python workflows.py <workflow> <url> <username> <password> [key=value ...]

    <workflow>  any workflow id from the dispatcher at the bottom (see also README.md)
    <url>       e.g. https://coordinator.example.com

Most workflows need only the connection details and run against the dispatcher's built-in
placeholder defaults. A few need environment-specific values to do anything real - an iSCSI
target address, an AD domain, a second pool to recover into - and take them as extra `key=value`
arguments after the password, overriding that workflow's default for the named parameter (e.g.
`create-iscsi-sr <url> <user> <pw> target=192.0.2.30`, `disaster-recovery <url> <user> <pw>
dr_url=https://standby-pool`). See each function's docstring for its parameters.
"""

import sys

from getting_started.connect_inventory import connect_inventory
from getting_started.events import events
from getting_started.wait_for_task import wait_for_task
from getting_started.error_handling import error_handling
from getting_started.trace_api_calls import trace_api_calls
from getting_started.find_by_uuid import find_by_uuid
from virtual_machines.create_vm import create_vm
from virtual_machines.vm_lifecycle import vm_lifecycle
from virtual_machines.manage_vm_disks import manage_vm_disks
from virtual_machines.snapshot_schedule import snapshot_schedule
from virtual_machines.manage_vm_groups import manage_vm_groups
from virtual_machines.snapshot_revert import snapshot_revert
from virtual_machines.edit_vm_properties import edit_vm_properties
from virtual_machines.new_vm_wizard import new_vm_wizard
from virtual_machines.copy_vm import copy_vm
from virtual_machines.create_vm_with_vgpu import create_vm_with_vgpu
from virtual_machines.clone_vm import clone_vm
from virtual_machines.delete_vm import delete_vm
from virtual_machines.checkpoint_vm import checkpoint_vm
from virtual_machines.list_templates import list_templates
from virtual_machines.rename_object import rename_object
from virtual_machines.vm_boot_config import vm_boot_config
from virtual_machines.convert_to_template import convert_to_template
from virtual_machines.cross_pool_copy_vm import cross_pool_copy_vm
from virtual_machines.vm_ip_address import vm_ip_address
from virtual_machines.manage_vapp import manage_vapp
from virtual_machines.attach_usb_device import attach_usb_device
from virtual_machines.manage_vtpm import manage_vtpm
from virtual_machines.export_import_vm import export_import_vm
from virtual_machines.configure_dynamic_memory import configure_dynamic_memory
from virtual_machines.manage_vm_media import manage_vm_media
from virtual_machines.vm_from_snapshot import vm_from_snapshot
from migration.live_migrate import live_migrate
from migration.storage_migrate import storage_migrate
from storage.create_nfs_sr import create_nfs_sr
from storage.attach_disk import attach_disk
from storage.sr_usage import sr_usage
from storage.vbd_inventory import vbd_inventory
from storage.reclaim_space import reclaim_space
from storage.create_iscsi_sr import create_iscsi_sr
from storage.create_smb_sr import create_smb_sr
from storage.create_hba_sr import create_hba_sr
from storage.create_iso_sr import create_iso_sr
from storage.changed_block_tracking import changed_block_tracking
from storage.manage_sr_lifecycle import manage_sr_lifecycle
from storage.reconnect_sr_storage import reconnect_sr_storage
from storage.export_import_vdi import export_import_vdi
from storage.set_default_sr import set_default_sr
from storage.attach_existing_disk import attach_existing_disk
from networking.create_network import create_network
from networking.manage_vif import manage_vif
from networking.list_networks import list_networks
from networking.create_bond import create_bond
from hosts_and_pools.dismiss_alerts import dismiss_alerts
from hosts_and_pools.host_power_on import host_power_on
from hosts_and_pools.rotate_pool_secret import rotate_pool_secret
from hosts_and_pools.change_root_password import change_root_password
from hosts_and_pools.manage_certificates import manage_certificates
from hosts_and_pools.host_maintenance import host_maintenance
from hosts_and_pools.configure_ha import configure_ha
from hosts_and_pools.gpu_inventory import gpu_inventory
from hosts_and_pools.read_metrics import read_metrics
from hosts_and_pools.host_info import host_info
from hosts_and_pools.pool_properties import pool_properties
from hosts_and_pools.pvs_accelerator import pvs_accelerator
from hosts_and_pools.rrd_metrics import rrd_metrics
from hosts_and_pools.configure_nrpe import configure_nrpe
from hosts_and_pools.configure_snmp import configure_snmp
from hosts_and_pools.wlb_recommendations import wlb_recommendations
from hosts_and_pools.configure_clustering import configure_clustering
from hosts_and_pools.manage_pool_membership import manage_pool_membership
from hosts_and_pools.configure_pvs_accelerator import configure_pvs_accelerator
from hosts_and_pools.manage_ssh_access import manage_ssh_access
from hosts_and_pools.control_domain_memory import control_domain_memory
from hosts_and_pools.backup_host_config import backup_host_config
from hosts_and_pools.server_status_report import server_status_report
from hosts_and_pools.restart_host import restart_host
from hosts_and_pools.manage_crash_dumps import manage_crash_dumps
from hosts_and_pools.configure_pool_options import configure_pool_options
from hosts_and_pools.configure_console_access import configure_console_access
from hosts_and_pools.configure_host_storage import configure_host_storage
from hosts_and_pools.configure_syslog import configure_syslog
from hosts_and_pools.manage_driver_variants import manage_driver_variants
from updates.configure_updates import configure_updates
from updates.configure_offline_updates import configure_offline_updates
from updates.apply_update import apply_update
from updates.rolling_pool_update import rolling_pool_update
from organization.tags_and_folders import tags_and_folders
from organization.custom_fields import custom_fields
from organization.pool_tags import pool_tags
from security_and_access.list_roles import list_roles
from security_and_access.manage_ad_users import manage_ad_users
from security_and_access.manage_secureboot_certificates import manage_secureboot_certificates
from disaster_recovery.disaster_recovery import disaster_recovery


def _wf(fn, **defaults):
    """Wrap a workflow function with its dispatcher's placeholder defaults, letting the
    command line override any of them by keyword."""
    def run(url, user, pw, **overrides):
        kwargs = dict(defaults)
        kwargs.update(overrides)
        return fn(url, user, pw, **kwargs)
    return run


WORKFLOWS = {
    "connect-inventory": _wf(connect_inventory),
    "create-vm": _wf(create_vm, template_name="Rocky Linux 8"),
    "vm-lifecycle": _wf(vm_lifecycle, source_vm="web-01"),
    "manage-vm-disks": _wf(manage_vm_disks, source_vm="web-01", sr_name="Shared NFS"),
    "dismiss-alerts": _wf(dismiss_alerts),
    "host-power-on": _wf(host_power_on),
    "rotate-pool-secret": _wf(rotate_pool_secret),
    "change-root-password": _wf(change_root_password),
    "manage-certificates": _wf(manage_certificates),
    "snapshot-schedule": _wf(snapshot_schedule, vm_name="web-01"),
    "manage-vm-groups": _wf(manage_vm_groups, vm_name="web-01"),
    "snapshot-revert": _wf(snapshot_revert, vm_name="web-01"),
    "create-nfs-sr": _wf(create_nfs_sr, nfs_server="192.0.2.10", nfs_path="/export/sdk"),
    "create-network": _wf(create_network),
    "edit-vm-properties": _wf(edit_vm_properties, vm_name="web-01"),
    "events": _wf(events, vm_name="web-01"),
    "new-vm-wizard": _wf(new_vm_wizard, template_name="Rocky Linux 8"),
    "live-migrate": _wf(live_migrate, source_vm="web-01", sr_name="Shared NFS"),
    "host-maintenance": _wf(host_maintenance, source_vm="web-01", sr_name="Shared NFS"),
    "configure-ha": _wf(configure_ha, heartbeat_sr_name="Shared NFS"),
    "copy-vm": _wf(copy_vm, vm_name="db-01", sr_name="Shared NFS"),
    "create-vm-with-vgpu": _wf(create_vm_with_vgpu, template_name="Rocky Linux 8"),
    "tags-and-folders": _wf(tags_and_folders, vm_name="web-01"),
    "configure-updates": _wf(configure_updates, repo_url="https://repo.ops.xenserver.com/xs9",
                             source_url="https://repo-src.ops.xenserver.com/xs9"),
    "configure-offline-updates": _wf(configure_offline_updates),
    "clone-vm": _wf(clone_vm, vm_name="db-01"),
    "delete-vm": _wf(delete_vm, template_name="Rocky Linux 8"),
    "storage-migrate": _wf(storage_migrate, source_vm="web-01"),
    "apply-update": _wf(apply_update, repo_url="https://repo.ops.xenserver.com/xs9",
                        source_url="https://repo-src.ops.xenserver.com/xs9"),
    "checkpoint-vm": _wf(checkpoint_vm, source_vm="web-01"),
    "attach-disk": _wf(attach_disk, template_name="Rocky Linux 8", sr_name="Shared NFS"),
    "wait-for-task": _wf(wait_for_task, template_name="Rocky Linux 8"),
    "error-handling": _wf(error_handling),
    "trace-api-calls": _wf(trace_api_calls),
    "list-templates": _wf(list_templates),
    "custom-fields": _wf(custom_fields, vm_name="web-01"),
    "gpu-inventory": _wf(gpu_inventory),
    "read-metrics": _wf(read_metrics),
    "rename-object": _wf(rename_object, vm_name="web-01"),
    "vm-boot-config": _wf(vm_boot_config, template_name="Rocky Linux 8"),
    "host-info": _wf(host_info),
    "list-roles": _wf(list_roles),
    "pool-properties": _wf(pool_properties),
    "sr-usage": _wf(sr_usage),
    "manage-vif": _wf(manage_vif, template_name="Rocky Linux 8"),
    "list-networks": _wf(list_networks),
    "vbd-inventory": _wf(vbd_inventory, vm_name="db-01"),
    "pool-tags": _wf(pool_tags),
    "convert-to-template": _wf(convert_to_template, template_name="Rocky Linux 8"),
    "find-by-uuid": _wf(find_by_uuid, vm_name="web-01"),
    "rolling-pool-update": _wf(rolling_pool_update, repo_url="https://repo.ops.xenserver.com/xs9",
                               source_url="https://repo-src.ops.xenserver.com/xs9"),
    "pvs-accelerator": _wf(pvs_accelerator),
    "configure-pvs-accelerator": _wf(configure_pvs_accelerator, vm_name="db-01"),
    "manage-ssh-access": _wf(manage_ssh_access),
    "manage-vtpm": _wf(manage_vtpm),
    "configure-dynamic-memory": _wf(configure_dynamic_memory),
    "manage-vm-media": _wf(manage_vm_media),
    "backup-host-config": _wf(backup_host_config),
    "manage-sr-lifecycle": _wf(manage_sr_lifecycle),
    "reconnect-sr-storage": _wf(reconnect_sr_storage),
    "export-import-vdi": _wf(export_import_vdi, sr_name="Shared NFS"),
    "set-default-sr": _wf(set_default_sr),
    "server-status-report": _wf(server_status_report),
    "disaster-recovery": _wf(disaster_recovery),
    "manage-secureboot-certificates": _wf(manage_secureboot_certificates),
    "restart-host": _wf(restart_host),
    "manage-crash-dumps": _wf(manage_crash_dumps),
    "configure-pool-options": _wf(configure_pool_options),
    "configure-console-access": _wf(configure_console_access),
    "configure-host-storage": _wf(configure_host_storage),
    "configure-syslog": _wf(configure_syslog),
    "manage-driver-variants": _wf(manage_driver_variants),
    "vm-from-snapshot": _wf(vm_from_snapshot, vm_name="db-01"),
    "attach-existing-disk": _wf(attach_existing_disk),
    "export-import-vm": _wf(export_import_vm, vm_name="db-01"),
    "changed-block-tracking": _wf(changed_block_tracking),
    "control-domain-memory": _wf(control_domain_memory),
    "rrd-metrics": _wf(rrd_metrics),
    "reclaim-space": _wf(reclaim_space),
    "vm-ip-address": _wf(vm_ip_address),
    "manage-ad-users": _wf(manage_ad_users, domain="", admin_user="alice",
                            admin_password="Password1", new_user="alice"),
    "create-iscsi-sr": _wf(create_iscsi_sr, target="192.0.2.30"),
    "create-smb-sr": _wf(create_smb_sr, server="192.0.2.40", share="/vmstore",
                          smb_username="Administrator", smb_password="Password1"),
    "create-hba-sr": _wf(create_hba_sr),
    "create-iso-sr": _wf(create_iso_sr, location="192.0.2.10:/isos"),
    "configure-nrpe": _wf(configure_nrpe),
    "configure-snmp": _wf(configure_snmp, trap_destination="192.0.2.50"),
    "configure-clustering": _wf(configure_clustering),
    "manage-pool-membership": _wf(manage_pool_membership),
    "create-bond": _wf(create_bond),
    "manage-vapp": _wf(manage_vapp, vm_name="db-01"),
    "attach-usb-device": _wf(attach_usb_device, vm_name="web-01"),
    "wlb-recommendations": _wf(wlb_recommendations, vm_name="web-01", wlb_host_port="wlb.example:8012",
                               wlb_username="wlbuser", wlb_password="wlbpass"),
}


def main():
    # cross-pool-copy-vm spans two pools, so it takes the destination pool's URL as a 5th argument,
    # then optionally that pool's credentials (if they differ from the source's) and the VM to copy.
    if len(sys.argv) >= 2 and sys.argv[1] == "cross-pool-copy-vm":
        if len(sys.argv) not in (6, 8, 9):
            print("usage: python workflows.py cross-pool-copy-vm <sourceUrl> <user> <password> <destUrl>"
                  " [<destUser> <destPassword> [<vmName>]]", file=sys.stderr)
            return 2
        dest_creds = sys.argv[6:8] if len(sys.argv) >= 8 else [None, None]
        cross_pool_copy_vm(sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5],
                           vm_name=sys.argv[8] if len(sys.argv) == 9 else "db-01",
                           dest_username=dest_creds[0], dest_password=dest_creds[1])
        return 0

    if len(sys.argv) < 5 or sys.argv[1] not in WORKFLOWS:
        print("usage: python workflows.py <%s|cross-pool-copy-vm> <url> <user> <password> "
              "[key=value ...]" % "|".join(WORKFLOWS), file=sys.stderr)
        return 2

    workflow, url, user, password = sys.argv[1:5]
    overrides = {}
    for arg in sys.argv[5:]:
        if "=" not in arg:
            print("extra arguments must be key=value (got %r)" % arg, file=sys.stderr)
            return 2
        key, value = arg.split("=", 1)
        overrides[key] = value
    WORKFLOWS[workflow](url, user, password, **overrides)
    return 0


if __name__ == "__main__":
    sys.exit(main())
