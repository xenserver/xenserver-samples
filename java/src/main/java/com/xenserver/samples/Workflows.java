// XenServer Java SDK - real-world workflow examples.
//
// Each example mirrors a task you would perform in XenCenter, driven through the XenServer
// Management API (XenAPI). The Java binding speaks JSON-RPC (Apache HttpClient 5 + Jackson).
//
// Each workflow is a class of its own, in a package per area (gettingstarted, virtualmachines,
// storage, ...). Its run method takes the connection details (and any object it acts on, looked up by
// name) as parameters, opens its own connection and logs out when done, so you can copy one into your
// own code along with PoolConnection (and any helper from Helpers it uses); its Javadoc shows the call.
// This class is only the command-line dispatcher, which lets one program run any of them.
//
// Usage:
//   java -cp <classpath> com.xenserver.samples.Workflows <workflow> <url> <username> <password>
//
//   <workflow>  any workflow id from the dispatcher (see also README.md)

package com.xenserver.samples;

import com.xenserver.samples.disasterrecovery.DisasterRecovery;
import com.xenserver.samples.gettingstarted.ConnectInventory;
import com.xenserver.samples.gettingstarted.ErrorHandling;
import com.xenserver.samples.gettingstarted.Events;
import com.xenserver.samples.gettingstarted.FindByUuid;
import com.xenserver.samples.gettingstarted.WaitForTask;
import com.xenserver.samples.hostsandpools.BackupHostConfig;
import com.xenserver.samples.hostsandpools.ChangeRootPassword;
import com.xenserver.samples.hostsandpools.ConfigureClustering;
import com.xenserver.samples.hostsandpools.ConfigureConsoleAccess;
import com.xenserver.samples.hostsandpools.ConfigureHa;
import com.xenserver.samples.hostsandpools.ConfigureHostStorage;
import com.xenserver.samples.hostsandpools.ConfigureNrpe;
import com.xenserver.samples.hostsandpools.ConfigurePoolOptions;
import com.xenserver.samples.hostsandpools.ConfigurePvsAccelerator;
import com.xenserver.samples.hostsandpools.ConfigureSnmp;
import com.xenserver.samples.hostsandpools.ConfigureSyslog;
import com.xenserver.samples.hostsandpools.ControlDomainMemory;
import com.xenserver.samples.hostsandpools.DismissAlerts;
import com.xenserver.samples.hostsandpools.GpuInventory;
import com.xenserver.samples.hostsandpools.HostInfo;
import com.xenserver.samples.hostsandpools.HostMaintenance;
import com.xenserver.samples.hostsandpools.HostPowerOn;
import com.xenserver.samples.hostsandpools.ManageCertificates;
import com.xenserver.samples.hostsandpools.ManageCrashDumps;
import com.xenserver.samples.hostsandpools.ManageDriverVariants;
import com.xenserver.samples.hostsandpools.ManagePoolMembership;
import com.xenserver.samples.hostsandpools.ManageSshAccess;
import com.xenserver.samples.hostsandpools.PoolProperties;
import com.xenserver.samples.hostsandpools.PvsAccelerator;
import com.xenserver.samples.hostsandpools.ReadMetrics;
import com.xenserver.samples.hostsandpools.RestartHost;
import com.xenserver.samples.hostsandpools.RotatePoolSecret;
import com.xenserver.samples.hostsandpools.RrdMetrics;
import com.xenserver.samples.hostsandpools.ServerStatusReport;
import com.xenserver.samples.hostsandpools.WlbRecommendations;
import com.xenserver.samples.migration.LiveMigrate;
import com.xenserver.samples.migration.StorageMigrate;
import com.xenserver.samples.networking.CreateBond;
import com.xenserver.samples.networking.CreateNetwork;
import com.xenserver.samples.networking.ListNetworks;
import com.xenserver.samples.networking.ManageVif;
import com.xenserver.samples.organization.CustomFields;
import com.xenserver.samples.organization.PoolTags;
import com.xenserver.samples.organization.TagsAndFolders;
import com.xenserver.samples.securityandaccess.ListRoles;
import com.xenserver.samples.securityandaccess.ManageAdUsers;
import com.xenserver.samples.securityandaccess.ManageSecurebootCertificates;
import com.xenserver.samples.storage.AttachDisk;
import com.xenserver.samples.storage.AttachExistingDisk;
import com.xenserver.samples.storage.ChangedBlockTracking;
import com.xenserver.samples.storage.CreateHbaSr;
import com.xenserver.samples.storage.CreateIscsiSr;
import com.xenserver.samples.storage.CreateIsoSr;
import com.xenserver.samples.storage.CreateNfsSr;
import com.xenserver.samples.storage.CreateSmbSr;
import com.xenserver.samples.storage.ExportImportVdi;
import com.xenserver.samples.storage.ManageSrLifecycle;
import com.xenserver.samples.storage.ReconnectSrStorage;
import com.xenserver.samples.storage.ReclaimSpace;
import com.xenserver.samples.storage.SetDefaultSr;
import com.xenserver.samples.storage.SrUsage;
import com.xenserver.samples.storage.VbdInventory;
import com.xenserver.samples.updates.ApplyUpdate;
import com.xenserver.samples.updates.ConfigureOfflineUpdates;
import com.xenserver.samples.updates.ConfigureUpdates;
import com.xenserver.samples.updates.RollingPoolUpdate;
import com.xenserver.samples.virtualmachines.AttachUsbDevice;
import com.xenserver.samples.virtualmachines.CheckpointVm;
import com.xenserver.samples.virtualmachines.CloneVm;
import com.xenserver.samples.virtualmachines.ConfigureDynamicMemory;
import com.xenserver.samples.virtualmachines.ConvertToTemplate;
import com.xenserver.samples.virtualmachines.CopyVm;
import com.xenserver.samples.virtualmachines.CreateVm;
import com.xenserver.samples.virtualmachines.CreateVmWithVgpu;
import com.xenserver.samples.virtualmachines.CrossPoolCopyVm;
import com.xenserver.samples.virtualmachines.DeleteVm;
import com.xenserver.samples.virtualmachines.EditVmProperties;
import com.xenserver.samples.virtualmachines.ExportImportVm;
import com.xenserver.samples.virtualmachines.ListTemplates;
import com.xenserver.samples.virtualmachines.ManageVapp;
import com.xenserver.samples.virtualmachines.ManageVmDisks;
import com.xenserver.samples.virtualmachines.ManageVmGroups;
import com.xenserver.samples.virtualmachines.ManageVmMedia;
import com.xenserver.samples.virtualmachines.ManageVtpm;
import com.xenserver.samples.virtualmachines.NewVmWizard;
import com.xenserver.samples.virtualmachines.RenameObject;
import com.xenserver.samples.virtualmachines.SnapshotRevert;
import com.xenserver.samples.virtualmachines.SnapshotSchedule;
import com.xenserver.samples.virtualmachines.VmBootConfig;
import com.xenserver.samples.virtualmachines.VmFromSnapshot;
import com.xenserver.samples.virtualmachines.VmIpAddress;
import com.xenserver.samples.virtualmachines.VmLifecycle;

import java.util.Map;

public final class Workflows {
    private Workflows() {
    }

    /**
     * Every workflow's dispatcher's placeholder defaults, keyed by its CLI parameter name (snake_case,
     * matching the Python reference) so `key=value` overrides after the password stay consistent across
     * every language's port of this dispatcher. Merged with any CLI-supplied overrides before the real
     * method is called - this is the Java equivalent of the Python reference's `_wf(fn, **defaults)`
     * wrapper.
     */
    private static Map<String, Map<String, String>> buildDefaults() {
        Map<String, Map<String, String>> d = new java.util.LinkedHashMap<>();
        d.put("connect-inventory", mapOf());
        d.put("create-vm", mapOf("template_name", "Rocky Linux 8", "new_vm_name", "sdk-example-vm"));
        d.put("vm-lifecycle", mapOf("source_vm", "web-01", "new_vm_name", "sdk-example-lifecycle"));
        d.put("manage-vm-disks", mapOf("source_vm", "web-01", "sr_name", "Shared NFS",
                "new_vm_name", "sdk-example-vm-disks"));
        d.put("dismiss-alerts", mapOf());
        d.put("host-power-on", mapOf());
        d.put("rotate-pool-secret", mapOf());
        d.put("change-root-password", mapOf());
        d.put("manage-certificates", mapOf());
        d.put("snapshot-schedule", mapOf("vm_name", "web-01", "schedule_name", "sdk-example-schedule"));
        d.put("manage-vm-groups", mapOf("vm_name", "web-01", "group_name", "sdk-example-group"));
        d.put("snapshot-revert", mapOf("vm_name", "web-01", "snapshot_name", "sdk-example-snapshot"));
        d.put("create-nfs-sr", mapOf("nfs_server", "192.0.2.10", "nfs_path", "/export/sdk",
                "sr_name", "sdk-example-nfs"));
        d.put("create-network", mapOf("network_name", "sdk-example-net"));
        d.put("edit-vm-properties", mapOf("vm_name", "web-01"));
        d.put("events", mapOf("vm_name", "web-01"));
        d.put("new-vm-wizard", mapOf("template_name", "Rocky Linux 8", "new_vm_name", "wizard-vm"));
        d.put("live-migrate", mapOf("source_vm", "web-01", "sr_name", "Shared NFS",
                "new_vm_name", "sdk-example-migrate"));
        d.put("host-maintenance", mapOf("source_vm", "web-01", "sr_name", "Shared NFS",
                "new_vm_name", "sdk-example-maint"));
        d.put("configure-ha", mapOf("heartbeat_sr_name", "Shared NFS"));
        d.put("copy-vm", mapOf("vm_name", "db-01", "sr_name", "Shared NFS", "copy_name", "sdk-example-copy"));
        d.put("create-vm-with-vgpu", mapOf("template_name", "Rocky Linux 8", "new_vm_name", "sdk-example-vgpu-vm"));
        d.put("tags-and-folders", mapOf("vm_name", "web-01"));
        d.put("configure-updates", mapOf("repo_url", "https://repo.ops.xenserver.com/xs9",
                "source_url", "https://repo-src.ops.xenserver.com/xs9"));
        d.put("clone-vm", mapOf("vm_name", "db-01", "clone_name", "sdk-example-clone"));
        d.put("delete-vm", mapOf("template_name", "Rocky Linux 8", "new_vm_name", "sdk-example-delete"));
        d.put("storage-migrate", mapOf("source_vm", "web-01", "new_vm_name", "sdk-example-storagemigrate"));
        d.put("apply-update", mapOf("repo_url", "https://repo.ops.xenserver.com/xs9",
                "source_url", "https://repo-src.ops.xenserver.com/xs9"));
        d.put("checkpoint-vm", mapOf("source_vm", "web-01", "new_vm_name", "sdk-example-checkpoint"));
        d.put("attach-disk", mapOf("template_name", "Rocky Linux 8", "sr_name", "Shared NFS",
                "new_vm_name", "sdk-example-attachdisk"));
        d.put("wait-for-task", mapOf("template_name", "Rocky Linux 8", "new_vm_name", "sdk-example-asynctask"));
        d.put("error-handling", mapOf());
        d.put("list-templates", mapOf());
        d.put("custom-fields", mapOf("vm_name", "web-01"));
        d.put("gpu-inventory", mapOf());
        d.put("read-metrics", mapOf());
        d.put("rename-object", mapOf("vm_name", "web-01"));
        d.put("vm-boot-config", mapOf("template_name", "Rocky Linux 8", "new_vm_name", "sdk-example-boot"));
        d.put("host-info", mapOf());
        d.put("list-roles", mapOf());
        d.put("pool-properties", mapOf());
        d.put("sr-usage", mapOf());
        d.put("manage-vif", mapOf("template_name", "Rocky Linux 8", "new_vm_name", "sdk-example-vif"));
        d.put("list-networks", mapOf());
        d.put("vbd-inventory", mapOf("vm_name", "db-01"));
        d.put("pool-tags", mapOf());
        d.put("convert-to-template", mapOf("template_name", "Rocky Linux 8", "new_vm_name", "sdk-example-totemplate"));
        d.put("find-by-uuid", mapOf("vm_name", "web-01"));
        d.put("rolling-pool-update", mapOf("repo_url", "https://repo.ops.xenserver.com/xs9",
                "source_url", "https://repo-src.ops.xenserver.com/xs9"));
        d.put("pvs-accelerator", mapOf());
        d.put("configure-pvs-accelerator", mapOf("vm_name", "db-01"));
        d.put("manage-ssh-access", mapOf());
        d.put("manage-vtpm", mapOf());
        d.put("configure-dynamic-memory", mapOf());
        d.put("manage-vm-media", mapOf());
        d.put("backup-host-config", mapOf());
        d.put("manage-sr-lifecycle", mapOf("nfs_server", "192.0.2.10", "nfs_path", "/export/spare"));
        d.put("reconnect-sr-storage", mapOf("nfs_server", "192.0.2.10", "nfs_path", "/export/spare"));
        d.put("export-import-vdi", mapOf("sr_name", "Shared NFS"));
        d.put("configure-offline-updates", mapOf());
        d.put("set-default-sr", mapOf("nfs_server", "192.0.2.10", "nfs_path", "/export/spare"));
        d.put("server-status-report", mapOf());
        d.put("disaster-recovery", mapOf()); // dr_url has no default - raised as an error if absent
        d.put("manage-secureboot-certificates", mapOf());
        d.put("restart-host", mapOf());
        d.put("manage-crash-dumps", mapOf());
        d.put("configure-pool-options", mapOf());
        d.put("configure-console-access", mapOf());
        d.put("configure-host-storage", mapOf());
        d.put("configure-syslog", mapOf("syslog_server", "192.0.2.50"));
        d.put("manage-driver-variants", mapOf());
        d.put("vm-from-snapshot", mapOf("vm_name", "db-01"));
        d.put("attach-existing-disk", mapOf());
        d.put("export-import-vm", mapOf("vm_name", "db-01"));
        d.put("changed-block-tracking", mapOf());
        d.put("control-domain-memory", mapOf());
        d.put("rrd-metrics", mapOf());
        d.put("reclaim-space", mapOf());
        d.put("vm-ip-address", mapOf("timeout", "60", "interval", "2"));
        d.put("manage-ad-users", mapOf("domain", "", "admin_user", "alice",
                "admin_password", "Password1", "new_user", "alice", "ldaps", "false"));
        d.put("create-iscsi-sr", mapOf("target", "192.0.2.30", "sr_name", "sdk-example-iscsi"));
        d.put("create-smb-sr", mapOf("server", "192.0.2.40", "share", "/vmstore",
                "smb_username", "Administrator", "smb_password", "Password1", "sr_name", "sdk-example-smb"));
        d.put("create-hba-sr", mapOf("scsi_id", "", "sr_name", "sdk-example-hba"));
        d.put("create-iso-sr", mapOf("location", "192.0.2.10:/isos"));
        d.put("configure-nrpe", mapOf());
        d.put("configure-snmp", mapOf("trap_destination", "192.0.2.50"));
        d.put("configure-clustering", mapOf());
        d.put("manage-pool-membership", mapOf());
        d.put("create-bond", mapOf());
        d.put("manage-vapp", mapOf("vm_name", "db-01"));
        d.put("attach-usb-device", mapOf("vm_name", "web-01"));
        d.put("wlb-recommendations", mapOf("vm_name", "web-01", "wlb_host_port", "wlb.example:8012",
                "wlb_username", "wlbuser", "wlb_password", "wlbpass", "wlb_certificate", ""));
        return d;
    }

    private static Map<String, String> mapOf(String... kv) {
        Map<String, String> m = new java.util.LinkedHashMap<>();
        for (int i = 0; i < kv.length; i += 2) m.put(kv[i], kv[i + 1]);
        return m;
    }

    /**
     * Maps the &lt;workflow&gt; argument to the matching workflow class, supplying the
     * concrete objects each one operates on. In your own code you would call these methods directly (see
     * the "Run it:" line under each) rather than through this dispatcher.
     */
    public static void main(String[] args) throws Exception {
        // cross-pool-copy-vm spans two pools, so it takes an extra 5th argument: the destination URL,
        // then optionally that pool's credentials (if they differ from the source's) and the VM to copy.
        // It keeps this positional form, unlike every other workflow.
        if (args.length >= 1 && args[0].equals("cross-pool-copy-vm")) {
            if (args.length != 5 && args.length != 7 && args.length != 8) {
                System.err.println("usage: java Workflows cross-pool-copy-vm <sourceUrl> <user> <password> <destUrl>"
                        + " [<destUser> <destPassword> [<vmName>]]");
                System.exit(2);
            }
            CrossPoolCopyVm.run(args[1], args[2], args[3], args[4], args.length == 8 ? args[7] : "db-01",
                    args.length >= 7 ? args[5] : null, args.length >= 7 ? args[6] : null);
            return;
        }

        Map<String, Map<String, String>> defaults = buildDefaults();
        if (args.length < 4 || !defaults.containsKey(args[0])) {
            System.err.println("usage: java Workflows <workflow> <url> <user> <password> [key=value ...]");
            System.err.println("  workflows: " + String.join("|", defaults.keySet()) + "|cross-pool-copy-vm");
            System.exit(2);
        }

        String workflow = args[0], url = args[1], user = args[2], password = args[3];
        Map<String, String> p = new java.util.LinkedHashMap<>(defaults.get(workflow));
        for (int i = 4; i < args.length; i++) {
            int eq = args[i].indexOf('=');
            if (eq < 0) {
                System.err.println("extra arguments must be key=value (got '" + args[i] + "')");
                System.exit(2);
            }
            p.put(args[i].substring(0, eq), args[i].substring(eq + 1));
        }

        switch (workflow) {
            case "connect-inventory": ConnectInventory.run(url, user, password); break;
            case "create-vm": CreateVm.run(url, user, password, p.get("template_name"), p.get("new_vm_name")); break;
            case "vm-lifecycle": VmLifecycle.run(url, user, password, p.get("source_vm"), p.get("new_vm_name")); break;
            case "manage-vm-disks":
                ManageVmDisks.run(url, user, password, p.get("source_vm"), p.get("sr_name"), p.get("new_vm_name")); break;
            case "dismiss-alerts": DismissAlerts.run(url, user, password); break;
            case "host-power-on": HostPowerOn.run(url, user, password); break;
            case "rotate-pool-secret": RotatePoolSecret.run(url, user, password); break;
            case "change-root-password": ChangeRootPassword.run(url, user, password); break;
            case "manage-certificates": ManageCertificates.run(url, user, password); break;
            case "snapshot-schedule":
                SnapshotSchedule.run(url, user, password, p.get("vm_name"), p.get("schedule_name")); break;
            case "manage-vm-groups":
                ManageVmGroups.run(url, user, password, p.get("vm_name"), p.get("group_name")); break;
            case "snapshot-revert":
                SnapshotRevert.run(url, user, password, p.get("vm_name"), p.get("snapshot_name")); break;
            case "create-nfs-sr":
                CreateNfsSr.run(url, user, password, p.get("nfs_server"), p.get("nfs_path"), p.get("sr_name")); break;
            case "create-network": CreateNetwork.run(url, user, password, p.get("network_name")); break;
            case "edit-vm-properties": EditVmProperties.run(url, user, password, p.get("vm_name")); break;
            case "events": Events.run(url, user, password, p.get("vm_name")); break;
            case "new-vm-wizard": NewVmWizard.run(url, user, password, p.get("template_name"), p.get("new_vm_name")); break;
            case "live-migrate": LiveMigrate.run(url, user, password, p.get("source_vm"), p.get("sr_name"), p.get("new_vm_name")); break;
            case "host-maintenance":
                HostMaintenance.run(url, user, password, p.get("source_vm"), p.get("sr_name"), p.get("new_vm_name")); break;
            case "configure-ha": ConfigureHa.run(url, user, password, p.get("heartbeat_sr_name")); break;
            case "copy-vm": CopyVm.run(url, user, password, p.get("vm_name"), p.get("sr_name"), p.get("copy_name")); break;
            case "create-vm-with-vgpu":
                CreateVmWithVgpu.run(url, user, password, p.get("template_name"), p.get("new_vm_name")); break;
            case "tags-and-folders": TagsAndFolders.run(url, user, password, p.get("vm_name")); break;
            case "configure-updates":
                ConfigureUpdates.run(url, user, password, p.get("repo_url"), p.get("source_url")); break;
            case "clone-vm": CloneVm.run(url, user, password, p.get("vm_name"), p.get("clone_name")); break;
            case "delete-vm": DeleteVm.run(url, user, password, p.get("template_name"), p.get("new_vm_name")); break;
            case "storage-migrate":
                StorageMigrate.run(url, user, password, p.get("source_vm"), p.get("new_vm_name")); break;
            case "apply-update":
                ApplyUpdate.run(url, user, password, p.get("repo_url"), p.get("source_url")); break;
            case "checkpoint-vm": CheckpointVm.run(url, user, password, p.get("source_vm"), p.get("new_vm_name")); break;
            case "attach-disk":
                AttachDisk.run(url, user, password, p.get("template_name"), p.get("sr_name"), p.get("new_vm_name")); break;
            case "wait-for-task": WaitForTask.run(url, user, password, p.get("template_name"), p.get("new_vm_name")); break;
            case "error-handling": ErrorHandling.run(url, user, password); break;
            case "list-templates": ListTemplates.run(url, user, password); break;
            case "custom-fields": CustomFields.run(url, user, password, p.get("vm_name")); break;
            case "gpu-inventory": GpuInventory.run(url, user, password); break;
            case "read-metrics": ReadMetrics.run(url, user, password); break;
            case "rename-object": RenameObject.run(url, user, password, p.get("vm_name")); break;
            case "vm-boot-config": VmBootConfig.run(url, user, password, p.get("template_name"), p.get("new_vm_name")); break;
            case "host-info": HostInfo.run(url, user, password); break;
            case "list-roles": ListRoles.run(url, user, password); break;
            case "pool-properties": PoolProperties.run(url, user, password); break;
            case "sr-usage": SrUsage.run(url, user, password); break;
            case "manage-vif": ManageVif.run(url, user, password, p.get("template_name"), p.get("new_vm_name")); break;
            case "list-networks": ListNetworks.run(url, user, password); break;
            case "vbd-inventory": VbdInventory.run(url, user, password, p.get("vm_name")); break;
            case "pool-tags": PoolTags.run(url, user, password); break;
            case "convert-to-template":
                ConvertToTemplate.run(url, user, password, p.get("template_name"), p.get("new_vm_name")); break;
            case "find-by-uuid": FindByUuid.run(url, user, password, p.get("vm_name")); break;
            case "rolling-pool-update":
                RollingPoolUpdate.run(url, user, password, p.get("repo_url"), p.get("source_url")); break;
            case "pvs-accelerator": PvsAccelerator.run(url, user, password); break;
            case "configure-pvs-accelerator": ConfigurePvsAccelerator.run(url, user, password, p.get("vm_name")); break;
            case "manage-ssh-access": ManageSshAccess.run(url, user, password); break;
            case "manage-vtpm": ManageVtpm.run(url, user, password); break;
            case "export-import-vm": ExportImportVm.run(url, user, password, p.get("vm_name")); break;
            case "configure-dynamic-memory": ConfigureDynamicMemory.run(url, user, password); break;
            case "manage-vm-media": ManageVmMedia.run(url, user, password); break;
            case "backup-host-config": BackupHostConfig.run(url, user, password); break;
            case "reconnect-sr-storage":
                ReconnectSrStorage.run(url, user, password, p.get("nfs_server"), p.get("nfs_path"),
                        p.get("new_nfs_server")); break;
            case "export-import-vdi": ExportImportVdi.run(url, user, password, p.get("sr_name")); break;
            case "configure-offline-updates":
                ConfigureOfflineUpdates.run(url, user, password, p.get("bundle_path")); break;
            case "manage-sr-lifecycle":
                ManageSrLifecycle.run(url, user, password, p.get("nfs_server"), p.get("nfs_path")); break;
            case "set-default-sr": SetDefaultSr.run(url, user, password, p.get("nfs_server"), p.get("nfs_path")); break;
            case "server-status-report": ServerStatusReport.run(url, user, password); break;
            case "disaster-recovery": DisasterRecovery.run(url, user, password, p.get("dr_url")); break;
            case "manage-secureboot-certificates": ManageSecurebootCertificates.run(url, user, password); break;
            case "restart-host": RestartHost.run(url, user, password); break;
            case "manage-crash-dumps": ManageCrashDumps.run(url, user, password); break;
            case "vm-from-snapshot": VmFromSnapshot.run(url, user, password, p.get("vm_name")); break;
            case "attach-existing-disk": AttachExistingDisk.run(url, user, password); break;
            case "changed-block-tracking": ChangedBlockTracking.run(url, user, password); break;
            case "control-domain-memory": ControlDomainMemory.run(url, user, password); break;
            case "rrd-metrics": RrdMetrics.run(url, user, password); break;
            case "reclaim-space": ReclaimSpace.run(url, user, password); break;
            case "vm-ip-address":
                VmIpAddress.run(url, user, password, Long.parseLong(p.get("timeout")) * 1000,
                        Long.parseLong(p.get("interval")) * 1000); break;
            case "manage-ad-users":
                ManageAdUsers.run(url, user, password, p.get("domain"), p.get("admin_user"),
                        p.get("admin_password"), p.get("new_user"), p.get("ldaps")); break;
            case "create-iscsi-sr":
                CreateIscsiSr.run(url, user, password, p.get("target"), p.get("port"), p.get("chap_user"),
                        p.get("chap_password"), p.get("target_iqn"), p.get("sr_name")); break;
            case "create-smb-sr":
                CreateSmbSr.run(url, user, password, p.get("server"), p.get("share"), p.get("smb_username"),
                        p.get("smb_password"), p.get("sr_name")); break;
            case "create-hba-sr": CreateHbaSr.run(url, user, password, p.get("scsi_id"), p.get("sr_name")); break;
            case "create-iso-sr": CreateIsoSr.run(url, user, password, p.get("location")); break;
            case "configure-nrpe": ConfigureNrpe.run(url, user, password); break;
            case "configure-snmp": ConfigureSnmp.run(url, user, password, p.get("trap_destination")); break;
            case "configure-clustering": ConfigureClustering.run(url, user, password); break;
            case "manage-pool-membership": ManagePoolMembership.run(url, user, password); break;
            case "create-bond": CreateBond.run(url, user, password); break;
            case "manage-vapp": ManageVapp.run(url, user, password, p.get("vm_name")); break;
            case "attach-usb-device": AttachUsbDevice.run(url, user, password, p.get("vm_name")); break;
            case "wlb-recommendations":
                WlbRecommendations.run(url, user, password, p.get("vm_name"), p.get("wlb_host_port"),
                        p.get("wlb_username"), p.get("wlb_password"), p.get("wlb_certificate")); break;
            case "configure-pool-options": ConfigurePoolOptions.run(url, user, password); break;
            case "configure-console-access": ConfigureConsoleAccess.run(url, user, password); break;
            case "configure-host-storage": ConfigureHostStorage.run(url, user, password); break;
            case "configure-syslog": ConfigureSyslog.run(url, user, password, p.get("syslog_server")); break;
            case "manage-driver-variants": ManageDriverVariants.run(url, user, password); break;
            default:
                System.err.println("unknown workflow: " + workflow);
                System.exit(2);
        }
    }
}
