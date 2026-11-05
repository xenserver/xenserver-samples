// XenServer .NET (C#) SDK - real-world workflow examples.
//
// Each workflow is a self-contained static method in its own file, in a folder per area
// (GettingStarted/, VirtualMachines/, Storage/, ...). It takes the connection details (and any object
// it acts on, looked up by name) as parameters, opens its own session and logs out when done, so you
// can copy one into your own code; the <example> in its documentation shows the call. Connection.cs
// has the shared connect helper and Helpers.cs the small helpers several workflows share.
//
// This file is only the command-line dispatcher, which lets one program run any workflow:
//
//   dotnet run -- <workflow> <url> <username> <password> [key=value ...]
//
//   <workflow>  any workflow id below (see also README.md)

using System;
using System.Collections.Generic;
using System.Linq;
using Console = System.Console; // XenAPI also defines a Console class
using static XenServerWorkflows.Workflows;

namespace XenServerWorkflows;

internal static class Program
{
    /// <summary>Merge CLI-supplied overrides onto a workflow's dispatcher defaults.</summary>
    private static Dictionary<string, string> Merge(Dictionary<string, string> defaults,
        Dictionary<string, string> overrides)
    {
        var result = new Dictionary<string, string>(defaults);
        foreach (var kv in overrides) result[kv.Key] = kv.Value;
        return result;
    }

    /// <summary>
    /// Maps the &lt;workflow&gt; argument to its method, merging the dispatcher's placeholder defaults with
    /// any key=value overrides supplied on the command line. In your own code you would call the methods
    /// directly (each one's &lt;example&gt; shows how) rather than through this dispatcher.
    /// </summary>
    private static readonly Dictionary<string, Action<string, string, string, Dictionary<string, string>>> ById = new()
    {
        ["connect-inventory"] = (u, n, p, ov) => ConnectInventory(u, n, p),
        ["create-vm"] = (u, n, p, ov) =>
        {
            var d = Merge(new() { ["template_name"] = "Rocky Linux 8", ["new_vm_name"] = "sdk-example-vm" }, ov);
            CreateVm(u, n, p, d["template_name"], d["new_vm_name"]);
        },
        ["vm-lifecycle"] = (u, n, p, ov) =>
        {
            var d = Merge(new() { ["source_vm"] = "web-01", ["new_vm_name"] = "sdk-example-lifecycle" }, ov);
            VmLifecycle(u, n, p, d["source_vm"], d["new_vm_name"]);
        },
        ["manage-vm-disks"] = (u, n, p, ov) =>
        {
            var d = Merge(new() { ["source_vm"] = "web-01", ["sr_name"] = "Shared NFS",
                                   ["new_vm_name"] = "sdk-example-vm-disks" }, ov);
            ManageVmDisks(u, n, p, d["source_vm"], d["sr_name"], d["new_vm_name"]);
        },
        ["dismiss-alerts"] = (u, n, p, ov) => DismissAlerts(u, n, p),
        ["host-power-on"] = (u, n, p, ov) => HostPowerOn(u, n, p),
        ["rotate-pool-secret"] = (u, n, p, ov) => RotatePoolSecret(u, n, p),
        ["change-root-password"] = (u, n, p, ov) => ChangeRootPassword(u, n, p),
        ["manage-certificates"] = (u, n, p, ov) => ManageCertificates(u, n, p),
        ["snapshot-schedule"] = (u, n, p, ov) =>
        {
            var d = Merge(new() { ["vm_name"] = "web-01", ["schedule_name"] = "sdk-example-schedule" }, ov);
            SnapshotSchedule(u, n, p, d["vm_name"], d["schedule_name"]);
        },
        ["manage-vm-groups"] = (u, n, p, ov) =>
        {
            var d = Merge(new() { ["vm_name"] = "web-01", ["group_name"] = "sdk-example-group" }, ov);
            ManageVmGroups(u, n, p, d["vm_name"], d["group_name"]);
        },
        ["snapshot-revert"] = (u, n, p, ov) =>
        {
            var d = Merge(new() { ["vm_name"] = "web-01", ["snapshot_name"] = "sdk-example-snapshot" }, ov);
            SnapshotRevert(u, n, p, d["vm_name"], d["snapshot_name"]);
        },
        ["create-nfs-sr"] = (u, n, p, ov) =>
        {
            var d = Merge(new() { ["nfs_server"] = "192.0.2.10", ["nfs_path"] = "/export/sdk",
                                   ["sr_name"] = "sdk-example-nfs" }, ov);
            CreateNfsSr(u, n, p, d["nfs_server"], d["nfs_path"], d["sr_name"]);
        },
        ["create-network"] = (u, n, p, ov) =>
        {
            var d = Merge(new() { ["network_name"] = "sdk-example-net" }, ov);
            CreateNetwork(u, n, p, d["network_name"]);
        },
        ["edit-vm-properties"] = (u, n, p, ov) =>
        {
            var d = Merge(new() { ["vm_name"] = "web-01" }, ov);
            EditVmProperties(u, n, p, d["vm_name"]);
        },
        ["events"] = (u, n, p, ov) =>
        {
            var d = Merge(new() { ["vm_name"] = "web-01" }, ov);
            Events(u, n, p, d["vm_name"]);
        },
        ["new-vm-wizard"] = (u, n, p, ov) =>
        {
            var d = Merge(new() { ["template_name"] = "Rocky Linux 8", ["new_vm_name"] = "wizard-vm" }, ov);
            NewVmWizard(u, n, p, d["template_name"], d["new_vm_name"]);
        },
        ["live-migrate"] = (u, n, p, ov) =>
        {
            var d = Merge(new() { ["source_vm"] = "web-01", ["sr_name"] = "Shared NFS",
                                   ["new_vm_name"] = "sdk-example-migrate" }, ov);
            LiveMigrate(u, n, p, d["source_vm"], d["sr_name"], d["new_vm_name"]);
        },
        ["host-maintenance"] = (u, n, p, ov) =>
        {
            var d = Merge(new() { ["source_vm"] = "web-01", ["sr_name"] = "Shared NFS",
                                   ["new_vm_name"] = "sdk-example-maint" }, ov);
            HostMaintenance(u, n, p, d["source_vm"], d["sr_name"], d["new_vm_name"]);
        },
        ["configure-ha"] = (u, n, p, ov) =>
        {
            var d = Merge(new() { ["heartbeat_sr_name"] = "Shared NFS" }, ov);
            ConfigureHa(u, n, p, d["heartbeat_sr_name"]);
        },
        ["copy-vm"] = (u, n, p, ov) =>
        {
            var d = Merge(new() { ["vm_name"] = "db-01", ["sr_name"] = "Shared NFS",
                                   ["copy_name"] = "sdk-example-copy" }, ov);
            CopyVm(u, n, p, d["vm_name"], d["sr_name"], d["copy_name"]);
        },
        ["create-vm-with-vgpu"] = (u, n, p, ov) =>
        {
            var d = Merge(new() { ["template_name"] = "Rocky Linux 8", ["new_vm_name"] = "sdk-example-vgpu-vm" }, ov);
            CreateVmWithVgpu(u, n, p, d["template_name"], d["new_vm_name"]);
        },
        ["tags-and-folders"] = (u, n, p, ov) =>
        {
            var d = Merge(new() { ["vm_name"] = "web-01" }, ov);
            TagsAndFolders(u, n, p, d["vm_name"]);
        },
        ["configure-updates"] = (u, n, p, ov) =>
        {
            var d = Merge(new() { ["repo_url"] = "https://repo.ops.xenserver.com/xs9",
                                   ["source_url"] = "https://repo-src.ops.xenserver.com/xs9" }, ov);
            ConfigureUpdates(u, n, p, d["repo_url"], d["source_url"]);
        },
        ["clone-vm"] = (u, n, p, ov) =>
        {
            var d = Merge(new() { ["vm_name"] = "db-01", ["clone_name"] = "sdk-example-clone" }, ov);
            CloneVm(u, n, p, d["vm_name"], d["clone_name"]);
        },
        ["delete-vm"] = (u, n, p, ov) =>
        {
            var d = Merge(new() { ["template_name"] = "Rocky Linux 8", ["new_vm_name"] = "sdk-example-delete" }, ov);
            DeleteVm(u, n, p, d["template_name"], d["new_vm_name"]);
        },
        ["storage-migrate"] = (u, n, p, ov) =>
        {
            var d = Merge(new() { ["source_vm"] = "web-01", ["new_vm_name"] = "sdk-example-storagemigrate" }, ov);
            StorageMigrate(u, n, p, d["source_vm"], d["new_vm_name"]);
        },
        ["apply-update"] = (u, n, p, ov) =>
        {
            var d = Merge(new() { ["repo_url"] = "https://repo.ops.xenserver.com/xs9",
                                   ["source_url"] = "https://repo-src.ops.xenserver.com/xs9" }, ov);
            ApplyUpdate(u, n, p, d["repo_url"], d["source_url"]);
        },
        ["checkpoint-vm"] = (u, n, p, ov) =>
        {
            var d = Merge(new() { ["source_vm"] = "web-01", ["new_vm_name"] = "sdk-example-checkpoint" }, ov);
            CheckpointVm(u, n, p, d["source_vm"], d["new_vm_name"]);
        },
        ["attach-disk"] = (u, n, p, ov) =>
        {
            var d = Merge(new() { ["template_name"] = "Rocky Linux 8", ["sr_name"] = "Shared NFS",
                                   ["new_vm_name"] = "sdk-example-attachdisk" }, ov);
            AttachDisk(u, n, p, d["template_name"], d["sr_name"], d["new_vm_name"]);
        },
        ["wait-for-task"] = (u, n, p, ov) =>
        {
            var d = Merge(new() { ["template_name"] = "Rocky Linux 8", ["new_vm_name"] = "sdk-example-asynctask" }, ov);
            WaitForTask(u, n, p, d["template_name"], d["new_vm_name"]);
        },
        ["error-handling"] = (u, n, p, ov) => ErrorHandling(u, n, p),
        ["trace-api-calls"] = (u, n, p, ov) => TraceApiCalls(u, n, p),
        ["list-templates"] = (u, n, p, ov) => ListTemplates(u, n, p),
        ["custom-fields"] = (u, n, p, ov) =>
        {
            var d = Merge(new() { ["vm_name"] = "web-01" }, ov);
            CustomFields(u, n, p, d["vm_name"]);
        },
        ["gpu-inventory"] = (u, n, p, ov) => GpuInventory(u, n, p),
        ["read-metrics"] = (u, n, p, ov) => ReadMetrics(u, n, p),
        ["rename-object"] = (u, n, p, ov) =>
        {
            var d = Merge(new() { ["vm_name"] = "web-01" }, ov);
            RenameObject(u, n, p, d["vm_name"]);
        },
        ["vm-boot-config"] = (u, n, p, ov) =>
        {
            var d = Merge(new() { ["template_name"] = "Rocky Linux 8", ["new_vm_name"] = "sdk-example-boot" }, ov);
            VmBootConfig(u, n, p, d["template_name"], d["new_vm_name"]);
        },
        ["host-info"] = (u, n, p, ov) => HostInfo(u, n, p),
        ["list-roles"] = (u, n, p, ov) => ListRoles(u, n, p),
        ["pool-properties"] = (u, n, p, ov) => PoolProperties(u, n, p),
        ["sr-usage"] = (u, n, p, ov) => SrUsage(u, n, p),
        ["manage-vif"] = (u, n, p, ov) =>
        {
            var d = Merge(new() { ["template_name"] = "Rocky Linux 8", ["new_vm_name"] = "sdk-example-vif" }, ov);
            ManageVif(u, n, p, d["template_name"], d["new_vm_name"]);
        },
        ["list-networks"] = (u, n, p, ov) => ListNetworks(u, n, p),
        ["vbd-inventory"] = (u, n, p, ov) =>
        {
            var d = Merge(new() { ["vm_name"] = "db-01" }, ov);
            VbdInventory(u, n, p, d["vm_name"]);
        },
        ["pool-tags"] = (u, n, p, ov) => PoolTags(u, n, p),
        ["convert-to-template"] = (u, n, p, ov) =>
        {
            var d = Merge(new() { ["template_name"] = "Rocky Linux 8", ["new_vm_name"] = "sdk-example-totemplate" }, ov);
            ConvertToTemplate(u, n, p, d["template_name"], d["new_vm_name"]);
        },
        ["find-by-uuid"] = (u, n, p, ov) =>
        {
            var d = Merge(new() { ["vm_name"] = "web-01" }, ov);
            FindByUuid(u, n, p, d["vm_name"]);
        },
        ["rolling-pool-update"] = (u, n, p, ov) =>
        {
            var d = Merge(new() { ["repo_url"] = "https://repo.ops.xenserver.com/xs9",
                                   ["source_url"] = "https://repo-src.ops.xenserver.com/xs9" }, ov);
            RollingPoolUpdate(u, n, p, d["repo_url"], d["source_url"]);
        },
        ["pvs-accelerator"] = (u, n, p, ov) => PvsAccelerator(u, n, p),
        ["configure-pvs-accelerator"] = (u, n, p, ov) =>
        {
            var d = Merge(new() { ["vm_name"] = "db-01" }, ov);
            ConfigurePvsAccelerator(u, n, p, d["vm_name"]);
        },
        ["manage-ssh-access"] = (u, n, p, ov) => ManageSshAccess(u, n, p),
        ["manage-vtpm"] = (u, n, p, ov) => ManageVtpm(u, n, p),
        ["export-import-vm"] = (u, n, p, ov) =>
        {
            var d = Merge(new() { ["vm_name"] = "db-01" }, ov);
            ExportImportVm(u, n, p, d["vm_name"]);
        },
        ["configure-dynamic-memory"] = (u, n, p, ov) => ConfigureDynamicMemory(u, n, p),
        ["manage-vm-media"] = (u, n, p, ov) => ManageVmMedia(u, n, p),
        ["backup-host-config"] = (u, n, p, ov) => BackupHostConfig(u, n, p),
        ["manage-sr-lifecycle"] = (u, n, p, ov) =>
        {
            var d = Merge(new() { ["nfs_server"] = "192.0.2.10", ["nfs_path"] = "/export/spare" }, ov);
            ManageSrLifecycle(u, n, p, d["nfs_server"], d["nfs_path"]);
        },
        ["reconnect-sr-storage"] = (u, n, p, ov) =>
        {
            var d = Merge(new() { ["nfs_server"] = "192.0.2.10", ["nfs_path"] = "/export/spare" }, ov);
            ReconnectSrStorage(u, n, p, d["nfs_server"], d["nfs_path"], ov.GetValueOrDefault("new_nfs_server"));
        },
        ["export-import-vdi"] = (u, n, p, ov) =>
        {
            var d = Merge(new() { ["sr_name"] = "Shared NFS" }, ov);
            ExportImportVdi(u, n, p, d["sr_name"]);
        },
        ["configure-offline-updates"] = (u, n, p, ov) =>
            ConfigureOfflineUpdates(u, n, p, ov.GetValueOrDefault("bundle_path")),
        ["set-default-sr"] = (u, n, p, ov) =>
        {
            var d = Merge(new() { ["nfs_server"] = "192.0.2.10", ["nfs_path"] = "/export/spare" }, ov);
            SetDefaultSr(u, n, p, d["nfs_server"], d["nfs_path"]);
        },
        ["server-status-report"] = (u, n, p, ov) => ServerStatusReport(u, n, p),
        ["configure-disaster-recovery"] = (u, n, p, ov) =>
            ConfigureDisasterRecovery(u, n, p, ov.GetValueOrDefault("sr_name")),
        ["disaster-recovery-failover"] = (u, n, p, ov) =>
        {
            var d = Merge(new()
            {
                ["target"] = "192.0.2.31", ["target_iqn"] = "iqn.2009-01.com.example:replica-0",
                ["scsi_id"] = "360a980004265656d5f4a2d63764e5738", ["sr_type"] = "lvmoiscsi", ["test_failover"] = "true",
            }, ov);
            DisasterRecoveryFailover(u, n, p, d["target"], d["target_iqn"], d["scsi_id"],
                ov.TryGetValue("port", out var port) ? int.Parse(port) : null, d["sr_type"],
                bool.Parse(d["test_failover"]));
        },
        ["manage-secureboot-certificates"] = (u, n, p, ov) => ManageSecurebootCertificates(u, n, p),
        ["restart-host"] = (u, n, p, ov) => RestartHost(u, n, p),
        ["manage-crash-dumps"] = (u, n, p, ov) => ManageCrashDumps(u, n, p),
        ["vm-from-snapshot"] = (u, n, p, ov) =>
        {
            var d = Merge(new() { ["vm_name"] = "db-01" }, ov);
            VmFromSnapshot(u, n, p, d["vm_name"]);
        },
        ["attach-existing-disk"] = (u, n, p, ov) => AttachExistingDisk(u, n, p),
        ["changed-block-tracking"] = (u, n, p, ov) => ChangedBlockTracking(u, n, p),
        ["control-domain-memory"] = (u, n, p, ov) => ControlDomainMemory(u, n, p),
        ["rrd-metrics"] = (u, n, p, ov) => RrdMetrics(u, n, p),
        ["reclaim-space"] = (u, n, p, ov) => ReclaimSpace(u, n, p),
        ["vm-ip-address"] = (u, n, p, ov) =>
        {
            var d = Merge(new() { ["timeout"] = "60", ["interval"] = "2" }, ov);
            VmIpAddress(u, n, p, int.Parse(d["timeout"]), int.Parse(d["interval"]));
        },
        ["manage-ad-users"] = (u, n, p, ov) =>
        {
            var d = Merge(new() { ["domain"] = "", ["admin_user"] = "alice", ["admin_password"] = "Password1",
                                   ["new_user"] = "alice", ["ldaps"] = "false" }, ov);
            ManageAdUsers(u, n, p, d["domain"], d["admin_user"], d["admin_password"], d["new_user"], d["ldaps"]);
        },
        ["create-iscsi-sr"] = (u, n, p, ov) =>
        {
            var d = Merge(new() { ["target"] = "192.0.2.30", ["scsi_id"] = "360a980004265656d5f4a2d63764e5734",
                                   ["sr_name"] = "sdk-example-iscsi" }, ov);
            int? port = ov.TryGetValue("port", out var portStr) ? int.Parse(portStr) : (int?)null;
            var chapUser = ov.TryGetValue("chap_user", out var cu) ? cu : null;
            var chapPassword = ov.TryGetValue("chap_password", out var cp) ? cp : null;
            CreateIscsiSr(u, n, p, d["target"], port, chapUser, chapPassword,
                ov.GetValueOrDefault("target_iqn"), d["scsi_id"], d["sr_name"]);
        },
        ["create-smb-sr"] = (u, n, p, ov) =>
        {
            var d = Merge(new() { ["server"] = "192.0.2.40", ["share"] = "/vmstore",
                                   ["smb_username"] = "Administrator", ["smb_password"] = "Password1",
                                   ["sr_name"] = "sdk-example-smb" }, ov);
            CreateSmbSr(u, n, p, d["server"], d["share"], d["smb_username"], d["smb_password"], d["sr_name"]);
        },
        ["create-hba-sr"] = (u, n, p, ov) =>
        {
            var d = Merge(new() { ["scsi_id"] = "", ["sr_name"] = "sdk-example-hba" }, ov);
            CreateHbaSr(u, n, p, d["scsi_id"], d["sr_name"]);
        },
        ["create-iso-sr"] = (u, n, p, ov) =>
        {
            var d = Merge(new() { ["location"] = "192.0.2.10:/isos" }, ov);
            CreateIsoSr(u, n, p, d["location"]);
        },
        ["configure-nrpe"] = (u, n, p, ov) => ConfigureNrpe(u, n, p),
        ["configure-snmp"] = (u, n, p, ov) =>
        {
            var d = Merge(new() { ["trap_destination"] = "192.0.2.50" }, ov);
            ConfigureSnmp(u, n, p, d["trap_destination"]);
        },
        ["configure-clustering"] = (u, n, p, ov) => ConfigureClustering(u, n, p),
        ["manage-pool-membership"] = (u, n, p, ov) => ManagePoolMembership(u, n, p),
        ["create-bond"] = (u, n, p, ov) => CreateBond(u, n, p),
        ["manage-vapp"] = (u, n, p, ov) =>
        {
            var d = Merge(new() { ["vm_name"] = "db-01" }, ov);
            ManageVapp(u, n, p, d["vm_name"]);
        },
        ["attach-usb-device"] = (u, n, p, ov) =>
        {
            var d = Merge(new() { ["vm_name"] = "web-01" }, ov);
            AttachUsbDevice(u, n, p, d["vm_name"]);
        },
        ["wlb-recommendations"] = (u, n, p, ov) =>
        {
            var d = Merge(new() { ["vm_name"] = "web-01", ["wlb_host_port"] = "wlb.example:8012",
                                   ["wlb_username"] = "wlbuser", ["wlb_password"] = "wlbpass",
                                   ["wlb_certificate"] = "" }, ov);
            WlbRecommendations(u, n, p, d["vm_name"], d["wlb_host_port"], d["wlb_username"], d["wlb_password"],
                                d["wlb_certificate"]);
        },
        ["configure-pool-options"] = (u, n, p, ov) => ConfigurePoolOptions(u, n, p),
        ["configure-console-access"] = (u, n, p, ov) => ConfigureConsoleAccess(u, n, p),
        ["configure-host-storage"] = (u, n, p, ov) => ConfigureHostStorage(u, n, p),
        ["configure-syslog"] = (u, n, p, ov) =>
        {
            var d = Merge(new() { ["syslog_server"] = "192.0.2.50" }, ov);
            ConfigureSyslog(u, n, p, d["syslog_server"]);
        },
        ["manage-driver-variants"] = (u, n, p, ov) => ManageDriverVariants(u, n, p),
    };

    private static int Main(string[] args)
    {
        // cross-pool-copy-vm is the one workflow that spans two pools, so it takes an extra 5th
        // argument: the destination pool URL, then optionally that pool's credentials (if they differ
        // from the source's) and the VM to copy. Every other workflow uses the uniform 4-arg contract.
        if (args.Length >= 1 && args[0] == "cross-pool-copy-vm")
        {
            if (args.Length != 5 && args.Length != 7 && args.Length != 8)
            {
                Console.Error.WriteLine(
                    "usage: dotnet run -- cross-pool-copy-vm <sourceUrl> <user> <password> <destUrl>" +
                    " [<destUser> <destPassword> [<vmName>]]");
                return 2;
            }
            CrossPoolCopyVm(args[1], args[2], args[3], args[4],
                args.Length == 8 ? args[7] : "db-01",
                args.Length >= 7 ? args[5] : null, args.Length >= 7 ? args[6] : null);
            return 0;
        }

        if (args.Length < 4 || !ById.ContainsKey(args[0]))
        {
            Console.Error.WriteLine(
                $"usage: dotnet run -- <{string.Join("|", ById.Keys)}|cross-pool-copy-vm> " +
                "<url> <user> <password> [key=value ...]");
            return 2;
        }

        var (workflow, url, user, password) = (args[0], args[1], args[2], args[3]);
        var overrides = new Dictionary<string, string>();
        foreach (var arg in args.Skip(4))
        {
            var idx = arg.IndexOf('=');
            if (idx < 0)
            {
                Console.Error.WriteLine($"extra arguments must be key=value (got '{arg}')");
                return 2;
            }
            overrides[arg.Substring(0, idx)] = arg.Substring(idx + 1);
        }
        ById[workflow](url, user, password, overrides);
        return 0;
    }
}
