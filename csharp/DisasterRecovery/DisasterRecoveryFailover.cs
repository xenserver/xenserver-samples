using System;
using System.Collections.Generic;
using System.Linq;
using System.Xml.Linq;
using XenAPI;
using Console = System.Console; // XenAPI also defines a Console class

namespace XenServerWorkflows;

internal static partial class Workflows
{
    /// <summary>
    /// On the pool at the disaster recovery site, attach the storage array's replica of the protected pool's
    /// storage, read the pool metadata replicated to it, and recover the VMs and vApps it describes. By
    /// default this is a test failover, which removes what it recovered and detaches the storage again.
    /// </summary>
    /// <example>
    /// <code>
    /// Workflows.DisasterRecoveryFailover("https://dr-site-pool", "root", password, "192.0.2.31",
    ///     "iqn.2009-01.com.example:replica-0", "360a98...");
    /// </code>
    /// </example>
    /// <remarks>
    /// <para>
    /// The replica is the LUN the storage array mirrors the protected pool's SR to: name it by the iSCSI
    /// target, IQN and SCSI id (srType "lvmoiscsi"), or by SCSI id alone for Fibre Channel/SAS (srType
    /// "lvmohba"). Before a real failover, break the mirror so that this site can write to the replica, and
    /// make sure no other pool has those LUNs attached: two pools using the same LUN corrupt it.
    /// </para>
    /// <para>
    /// DR_task.create attaches every SR on the LUN that you name (by uuid) to this pool, keeping its uuid,
    /// and VDI.open_database gives a session onto the metadata replicated there - a separate, read-only
    /// database, not this pool. Recovering runs on that session and names this pool's session as the place
    /// to recover into. A test failover then removes the recovered VMs and vApps - not their disks, which are
    /// the replica's - and detaches and forgets the SRs.
    /// </para>
    /// </remarks>
    public static void DisasterRecoveryFailover(string url, string user, string password, string target,
        string targetIqn, string scsiId, int? port = null, string srType = "lvmoiscsi", bool testFailover = true)
    {
        var session = Connect(url, user, password);

        var deviceConfig = new Dictionary<string, string> { ["SCSIid"] = scsiId };
        if (srType == "lvmoiscsi")
        {
            deviceConfig["target"] = target;
            deviceConfig["targetIQN"] = targetIqn;
            if (port.HasValue) deviceConfig["port"] = port.Value.ToString();
        }

        // Which SRs are on the LUN, and which of them hold pool metadata. sm_config metadata=true asks for
        // their names and the pool_metadata_detected flag as well as their uuids.
        var master = Pool.get_master(session, Pool.get_all(session)[0].opaque_ref).opaque_ref;
        var found = XDocument.Parse(SR.probe(session, master, deviceConfig, srType,
            new Dictionary<string, string> { ["metadata"] = "true" }));
        var srs = found.Descendants("SR").Select(e => (
            Uuid: e.Element("UUID")!.Value.Trim(),
            Name: e.Element("name_label")?.Value.Trim() ?? "",
            HasMetadata: e.Element("pool_metadata_detected")?.Value.Trim() == "true")).ToList();
        foreach (var (uuid, srName, hasMetadata) in srs)
            Console.WriteLine($"Found SR {srName} ({uuid}){(hasMetadata ? ", with pool metadata" : "")}");
        if (srs.Count == 0)
            throw new Exception("there is no SR on that LUN");

        var task = DR_task.create(session, srType, deviceConfig, srs.Select(s => s.Uuid).ToArray()).opaque_ref;
        var introduced = DR_task.get_introduced_SRs(session, task).Select(r => r.opaque_ref).ToList();
        Console.WriteLine($"Attached {string.Join(", ", introduced.Select(sr => SR.get_name_label(session, sr)))}");

        // Recover from every replicated database on the attached SRs: vApps first (their VMs come with them),
        // then the VMs not in a vApp. A VM whose disks are on storage this pool hasn't attached can't be
        // recovered - assert_can_be_recovered says so (VM_REQUIRES_SR) - so skip it.
        var recoveredVms = new List<string>();
        var recoveredVapps = new List<string>();
        foreach (var sr in introduced)
        {
            foreach (var vdi in SR.get_VDIs(session, sr).Select(v => v.opaque_ref))
            {
                if (VDI.get_type(session, vdi) != vdi_type.metadata || !VDI.get_metadata_latest(session, vdi))
                    continue;
                // A session onto the replicated database, made from the id open_database returns.
                var database = new Session(url) { opaque_ref = VDI.open_database(session, vdi).opaque_ref };
                database.JsonRpcClient.ServerCertificateValidationCallback = (req, cert, chain, errors) => true;

                // A pool often has no name of its own; show its coordinator's name instead.
                var pool = Pool.get_all(database)[0].opaque_ref;
                var poolName = Pool.get_name_label(database, pool);
                if (string.IsNullOrEmpty(poolName))
                    poolName = Host.get_name_label(database, Pool.get_master(database, pool).opaque_ref);
                Console.WriteLine($"  pool metadata of {poolName}");

                var inRecoveredVapp = new HashSet<string>();
                foreach (var (vapp, record) in VM_appliance.get_all_records(database))
                {
                    try { VM_appliance.assert_can_be_recovered(database, vapp.opaque_ref, session.opaque_ref); }
                    catch (Failure e)
                    {
                        Console.WriteLine($"  cannot recover vApp {record.name_label}: {e.ErrorDescription[0]}");
                        continue;
                    }
                    VM_appliance.recover(database, vapp.opaque_ref, session.opaque_ref, false);
                    recoveredVapps.Add(record.uuid);
                    foreach (var vm in record.VMs)
                    {
                        recoveredVms.Add(VM.get_uuid(database, vm.opaque_ref));
                        inRecoveredVapp.Add(vm.opaque_ref);
                    }
                    Console.WriteLine($"  recovered vApp {record.name_label}");
                }

                foreach (var (vm, record) in VM.get_all_records(database).OrderBy(kv => kv.Value.name_label))
                {
                    if (record.is_a_template || record.is_control_domain || record.is_a_snapshot
                        || inRecoveredVapp.Contains(vm.opaque_ref))
                        continue;
                    try { VM.assert_can_be_recovered(database, vm.opaque_ref, session.opaque_ref); }
                    catch (Failure e)
                    {
                        Console.WriteLine($"  cannot recover {record.name_label}: {e.ErrorDescription[0]}");
                        continue;
                    }
                    VM.recover(database, vm.opaque_ref, session.opaque_ref, false);
                    recoveredVms.Add(record.uuid);
                    Console.WriteLine($"  recovered {record.name_label}");
                }
                database.logout();
            }
        }

        // The recovered VMs keep their uuids, so look them up by uuid - a name may be taken here already.
        foreach (var uuid in recoveredVms)
        {
            var vm = VM.get_by_uuid(session, uuid).opaque_ref;
            Console.WriteLine($"{VM.get_name_label(session, vm)} is {VM.get_power_state(session, vm)}");
        }

        if (testFailover)
        {
            foreach (var uuid in recoveredVms)
            {
                var vm = VM.get_by_uuid(session, uuid).opaque_ref;
                if (VM.get_power_state(session, vm) != vm_power_state.Halted)
                    VM.hard_shutdown(session, vm);
                VM.destroy(session, vm);
            }
            foreach (var uuid in recoveredVapps)
                VM_appliance.destroy(session, VM_appliance.get_by_uuid(session, uuid).opaque_ref);
        }
        // Destroying the task detaches and forgets the SRs it attached that no recovered VM needs.
        DR_task.destroy(session, task);
        if (testFailover)
        {
            // The SRs the recovered VMs needed are no longer the task's: detach and forget those too.
            foreach (var sr in introduced)
            {
                try
                {
                    foreach (var pbd in SR.get_PBDs(session, sr))
                        if (PBD.get_currently_attached(session, pbd.opaque_ref))
                            PBD.unplug(session, pbd.opaque_ref);
                    SR.forget(session, sr);
                }
                catch (Failure e) when (e.ErrorDescription[0] == "HANDLE_INVALID")
                {
                    // already forgotten by DR_task.destroy
                }
            }
            Console.WriteLine("Test failover: removed the recovered VMs and detached the replica");
        }
        else
            Console.WriteLine("Recovered VMs are halted: start them when you are ready");
        Console.WriteLine("OK: disaster-recovery-failover");
        session.logout();
    }
}
