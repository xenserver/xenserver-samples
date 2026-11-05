<!-- Generated from workflows.json, the example sources and a run of each example. Edit those, not this file. -->

# Fail over to a disaster recovery site

On the pool at the disaster recovery site, attach the storage array's replica of the protected pool's storage, read the pool metadata replicated to it, and recover the VMs and vApps it describes. By default it is a test failover, which removes what it recovered and detaches the replica again.

**Requires:** a pool at the disaster recovery site, and the storage array's replica of the protected pool's iSCSI or Fibre Channel SR (target, IQN and SCSI id), with the mirror broken.

**Caution:** never attach a LUN that another pool still has attached: two pools using one LUN corrupt it.

Workflow `disaster-recovery-failover`. [All workflows](README.md) · [Connecting](connecting.md)

## C# (.NET)

Source: [`csharp/DisasterRecovery/DisasterRecoveryFailover.cs`](../../csharp/DisasterRecovery/DisasterRecoveryFailover.cs)

```csharp
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
/// the replica's - and detaches and forgets the SRs, as the wizard does.
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
```

<details><summary>Example output</summary>

```text
Found SR DR storage (000003e9-0000-0000-0600-000000000000), with pool metadata
Attached DR storage
  pool metadata of protected-pool
  recovered app-01
  cannot recover db-01: VM_REQUIRES_SR
app-01 is Halted
Test failover: removed the recovered VMs and detached the replica
OK: disaster-recovery-failover
```

</details>

## Python

Source: [`python/disaster_recovery/disaster_recovery_failover.py`](../../python/disaster_recovery/disaster_recovery_failover.py)

```python
"""Fail over to the disaster recovery site.

On the pool at the disaster recovery site, attach the storage array's replica of the protected pool's
storage, read the pool metadata replicated to it, and recover the VMs and vApps it describes. By default
this is a test failover, which removes what it recovered and detaches the storage again.

Run it::

    disaster_recovery_failover("https://dr-site-pool", "root", password, target="192.0.2.31",
                               target_iqn="iqn.2009-01.com.example:replica-0", scsi_id="360a98...")
"""

import xml.etree.ElementTree as ET

import XenAPI

from connection import connect


def disaster_recovery_failover(url, username, password, target=None, target_iqn=None, scsi_id=None,
                               port=None, sr_type="lvmoiscsi", test_failover=True):
    """Recover the protected pool's VMs and vApps into this pool from the replica of its storage.

    The replica is the LUN the storage array mirrors the protected pool's SR to: name it by the iSCSI
    target, IQN and SCSI id (sr_type "lvmoiscsi"), or by SCSI id alone for Fibre Channel/SAS (sr_type
    "lvmohba"). Before a real failover, break the mirror so that this site can write to the replica, and
    make sure no other pool has those LUNs attached: two pools using the same LUN corrupt it.

    DR_task.create attaches every SR on the LUN that you name (by uuid) to this pool, keeping its uuid,
    and VDI.open_database gives a session onto the metadata replicated there - a separate, read-only
    database, not this pool. Recovering runs on that session and names this pool's session as the place
    to recover into. A test failover (test_failover=True) then removes the recovered VMs and vApps -
    not their disks, which are the replica's - and detaches and forgets the SRs, as the wizard does."""
    if isinstance(test_failover, str):  # from the command line
        test_failover = test_failover.lower() != "false"
    session = connect(url, username, password)
    x = session.xenapi

    device_config = {"SCSIid": scsi_id}
    if sr_type == "lvmoiscsi":
        device_config.update({"target": target, "targetIQN": target_iqn})
        if port:
            device_config["port"] = str(port)

    # Which SRs are on the LUN, and which of them hold pool metadata. sm_config metadata=true asks for
    # their names and the pool_metadata_detected flag as well as their uuids.
    master = x.pool.get_master(x.pool.get_all()[0])
    found = ET.fromstring(x.SR.probe(master, device_config, sr_type, {"metadata": "true"}))
    srs = [(e.findtext("UUID").strip(), (e.findtext("name_label") or "").strip(),
            (e.findtext("pool_metadata_detected") or "").strip() == "true") for e in found.iter("SR")]
    for uuid, name, has_metadata in srs:
        print("Found SR %s (%s)%s" % (name, uuid, ", with pool metadata" if has_metadata else ""))
    if not srs:
        raise RuntimeError("there is no SR on that LUN")

    task = x.DR_task.create(sr_type, device_config, [uuid for uuid, _, _ in srs])
    introduced = x.DR_task.get_introduced_SRs(task)
    print("Attached %s" % ", ".join(x.SR.get_name_label(sr) for sr in introduced))

    # Recover from every replicated database on the attached SRs: vApps first (their VMs come with
    # them), then the VMs not in a vApp. A VM whose disks are on storage this pool hasn't attached
    # can't be recovered - assert_can_be_recovered says so (VM_REQUIRES_SR) - so skip it.
    recovered_vms, recovered_vapps = [], []
    for sr in introduced:
        for vdi in x.SR.get_VDIs(sr):
            if x.VDI.get_type(vdi) != "metadata" or not x.VDI.get_metadata_latest(vdi):
                continue
            database = XenAPI.Session(url, ignore_ssl=True)
            database._session = x.VDI.open_database(vdi)
            d = database.xenapi
            # A pool often has no name of its own; show its coordinator's name instead.
            pool = d.pool.get_all()[0]
            print("  pool metadata of %s" % (d.pool.get_name_label(pool)
                                             or d.host.get_name_label(d.pool.get_master(pool))))

            in_recovered_vapp = set()
            for vapp, record in d.VM_appliance.get_all_records().items():
                try:
                    d.VM_appliance.assert_can_be_recovered(vapp, session._session)
                except XenAPI.Failure as e:
                    print("  cannot recover vApp %s: %s" % (record["name_label"], e.details[0]))
                    continue
                d.VM_appliance.recover(vapp, session._session, False)
                recovered_vapps.append(record["uuid"])
                recovered_vms.extend(d.VM.get_uuid(vm) for vm in record["VMs"])
                in_recovered_vapp.update(record["VMs"])
                print("  recovered vApp %s" % record["name_label"])

            for vm, record in sorted(d.VM.get_all_records().items(), key=lambda kv: kv[1]["name_label"]):
                if (record["is_a_template"] or record["is_control_domain"] or record["is_a_snapshot"]
                        or vm in in_recovered_vapp):
                    continue
                try:
                    d.VM.assert_can_be_recovered(vm, session._session)
                except XenAPI.Failure as e:
                    print("  cannot recover %s: %s" % (record["name_label"], e.details[0]))
                    continue
                d.VM.recover(vm, session._session, False)
                recovered_vms.append(record["uuid"])
                print("  recovered %s" % record["name_label"])
            # Close the database. The binding's own logout is for sessions it logged in itself, so
            # make the call directly.
            database.session.logout(database._session)

    # The recovered VMs keep their uuids, so look them up by uuid - a name may be taken here already.
    for uuid in recovered_vms:
        vm = x.VM.get_by_uuid(uuid)
        print("%s is %s" % (x.VM.get_name_label(vm), x.VM.get_power_state(vm)))

    if test_failover:
        for uuid in recovered_vms:
            vm = x.VM.get_by_uuid(uuid)
            if x.VM.get_power_state(vm) != "Halted":
                x.VM.hard_shutdown(vm)
            x.VM.destroy(vm)
        for uuid in recovered_vapps:
            x.VM_appliance.destroy(x.VM_appliance.get_by_uuid(uuid))
    # Destroying the task detaches and forgets the SRs it attached that no recovered VM needs.
    x.DR_task.destroy(task)
    if test_failover:
        # The SRs the recovered VMs needed are no longer the task's: detach and forget those too.
        for sr in introduced:
            try:
                for pbd in x.SR.get_PBDs(sr):
                    if x.PBD.get_currently_attached(pbd):
                        x.PBD.unplug(pbd)
                x.SR.forget(sr)
            except XenAPI.Failure as e:
                if e.details[0] != "HANDLE_INVALID":  # already forgotten by DR_task.destroy
                    raise
        print("Test failover: removed the recovered VMs and detached the replica")
    else:
        print("Recovered VMs are halted: start them when you are ready")
    print("OK: disaster-recovery-failover")
    session.logout()
```

<details><summary>Example output</summary>

```text
Found SR DR storage (000003e9-0000-0000-0600-000000000000), with pool metadata
Attached DR storage
  pool metadata of protected-pool
  recovered app-01
  cannot recover db-01: VM_REQUIRES_SR
app-01 is Halted
Test failover: removed the recovered VMs and detached the replica
OK: disaster-recovery-failover
```

</details>

## Java

Source: [`java/src/main/java/com/xenserver/samples/disasterrecovery/DisasterRecoveryFailover.java`](../../java/src/main/java/com/xenserver/samples/disasterrecovery/DisasterRecoveryFailover.java)

```java
package com.xenserver.samples.disasterrecovery;

import com.fasterxml.jackson.core.type.TypeReference;
import com.xensource.xenapi.Connection;
import com.xensource.xenapi.DRTask;
import com.xensource.xenapi.Host;
import com.xensource.xenapi.PBD;
import com.xensource.xenapi.Pool;
import com.xensource.xenapi.SR;
import com.xensource.xenapi.Session;
import com.xensource.xenapi.Types;
import com.xensource.xenapi.VDI;
import com.xensource.xenapi.VM;
import com.xensource.xenapi.VMAppliance;

import org.w3c.dom.Element;
import org.w3c.dom.NodeList;

import java.io.ByteArrayInputStream;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.HashSet;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.StringJoiner;
import javax.xml.parsers.DocumentBuilderFactory;

import static com.xenserver.samples.Helpers.firstTagText;
import static com.xenserver.samples.PoolConnection.connect;

public final class DisasterRecoveryFailover {
    private DisasterRecoveryFailover() {
    }

    /**
     * Fail over to the disaster recovery site.
     *
     * <p>On the pool at the disaster recovery site, attach the storage array's replica of the protected
     * pool's storage, read the pool metadata replicated to it, and recover the VMs and vApps it
     * describes. By default this is a test failover, which removes what it recovered and detaches the
     * storage again.
     *
     * <p>The replica is the LUN the storage array mirrors the protected pool's SR to: name it by the iSCSI
     * target, IQN and SCSI id (srType "lvmoiscsi"), or by SCSI id alone for Fibre Channel/SAS (srType
     * "lvmohba"). Before a real failover, break the mirror so that this site can write to the replica, and
     * make sure no other pool has those LUNs attached: two pools using the same LUN corrupt it.
     *
     * <p>DR_task.create attaches every SR on the LUN that you name (by uuid) to this pool, keeping its
     * uuid, and VDI.open_database gives a session onto the metadata replicated there - a separate,
     * read-only database, not this pool. Recovering runs on that session and names this pool's session as
     * the place to recover into. A test failover then removes the recovered VMs and vApps - not their
     * disks, which are the replica's - and detaches and forgets the SRs, as the wizard does.
     *
     * <p>Run it:
     *
     * <pre>{@code
     * DisasterRecoveryFailover.run("https://dr-site-pool", "root", password, "192.0.2.31",
     *     "iqn.2009-01.com.example:replica-0", "360a98...", null, "lvmoiscsi", true);
     * }</pre>
     */
    public static void run(String url, String user, String password, String target, String targetIqn,
                           String scsiId, String port, String srType, boolean testFailover) throws Exception {
        Connection conn = connect(url, user, password);
        try {
            Map<String, String> deviceConfig = new HashMap<>();
            deviceConfig.put("SCSIid", scsiId);
            if ("lvmoiscsi".equals(srType)) {
                deviceConfig.put("target", target);
                deviceConfig.put("targetIQN", targetIqn);
                if (port != null && !port.isEmpty()) deviceConfig.put("port", port);
            }

            // Which SRs are on the LUN, and which of them hold pool metadata. sm_config metadata=true asks
            // for their names and the pool_metadata_detected flag as well as their uuids.
            Host master = Pool.getAll(conn).iterator().next().getMaster(conn);
            String xml = SR.probe(conn, master, deviceConfig, srType, Map.of("metadata", "true"));
            NodeList found = DocumentBuilderFactory.newInstance().newDocumentBuilder()
                    .parse(new ByteArrayInputStream(xml.getBytes(StandardCharsets.UTF_8)))
                    .getElementsByTagName("SR");
            Set<String> uuids = new LinkedHashSet<>();
            for (int i = 0; i < found.getLength(); i++) {
                Element e = (Element) found.item(i);
                String uuid = firstTagText(e, "UUID").trim();
                String name = firstTagText(e, "name_label");
                boolean hasMetadata = "true".equals(String.valueOf(firstTagText(e, "pool_metadata_detected")).trim());
                System.out.println("Found SR " + (name == null ? "" : name.trim()) + " (" + uuid + ")"
                        + (hasMetadata ? ", with pool metadata" : ""));
                uuids.add(uuid);
            }
            if (uuids.isEmpty()) throw new RuntimeException("there is no SR on that LUN");

            DRTask task = DRTask.create(conn, srType, deviceConfig, uuids);
            Set<SR> introduced = task.getIntroducedSRs(conn);
            StringJoiner attached = new StringJoiner(", ");
            for (SR sr : introduced) attached.add(sr.getNameLabel(conn));
            System.out.println("Attached " + attached);

            // Recover from every replicated database on the attached SRs: vApps first (their VMs come with
            // them), then the VMs not in a vApp. A VM whose disks are on storage this pool hasn't attached
            // can't be recovered - assert_can_be_recovered says so (VM_REQUIRES_SR) - so skip it.
            String sessionTo = conn.getSessionReference();
            List<String> recoveredVms = new ArrayList<>();
            List<String> recoveredVapps = new ArrayList<>();
            for (SR sr : introduced) {
                for (VDI vdi : sr.getVDIs(conn)) {
                    if (vdi.getType(conn) != Types.VdiType.METADATA || !vdi.getMetadataLatest(conn)) continue;
                    Database db = new Database(conn, vdi.openDatabase(conn));

                    // A pool often has no name of its own; show its coordinator's name instead.
                    Pool.Record pool = db.call("pool.get_all_records", new TypeReference<Map<Pool, Pool.Record>>() {})
                            .values().iterator().next();
                    String poolName = pool.nameLabel.isEmpty()
                            ? db.call("host.get_name_label", new TypeReference<String>() {}, pool.master.toWireString())
                            : pool.nameLabel;
                    System.out.println("  pool metadata of " + poolName);

                    Set<String> inRecoveredVapp = new HashSet<>();
                    Map<VMAppliance, VMAppliance.Record> vapps =
                            db.call("VM_appliance.get_all_records", new TypeReference<Map<VMAppliance, VMAppliance.Record>>() {});
                    for (Map.Entry<VMAppliance, VMAppliance.Record> e : vapps.entrySet()) {
                        String vapp = e.getKey().toWireString();
                        try {
                            db.call("VM_appliance.assert_can_be_recovered", vapp, sessionTo);
                        } catch (Types.XenAPIException cannot) {
                            System.out.println("  cannot recover vApp " + e.getValue().nameLabel + ": " + code(cannot));
                            continue;
                        }
                        db.call("VM_appliance.recover", vapp, sessionTo, false);
                        recoveredVapps.add(e.getValue().uuid);
                        for (VM vm : e.getValue().VMs) {
                            recoveredVms.add(db.call("VM.get_uuid", new TypeReference<String>() {}, vm.toWireString()));
                            inRecoveredVapp.add(vm.toWireString());
                        }
                        System.out.println("  recovered vApp " + e.getValue().nameLabel);
                    }

                    List<Map.Entry<VM, VM.Record>> vms = new ArrayList<>(
                            db.call("VM.get_all_records", new TypeReference<Map<VM, VM.Record>>() {}).entrySet());
                    vms.sort(Map.Entry.comparingByValue((a, b) -> a.nameLabel.compareTo(b.nameLabel)));
                    for (Map.Entry<VM, VM.Record> e : vms) {
                        VM.Record r = e.getValue();
                        String vm = e.getKey().toWireString();
                        if (r.isATemplate || r.isControlDomain || r.isASnapshot || inRecoveredVapp.contains(vm))
                            continue;
                        try {
                            db.call("VM.assert_can_be_recovered", vm, sessionTo);
                        } catch (Types.XenAPIException cannot) {
                            System.out.println("  cannot recover " + r.nameLabel + ": " + code(cannot));
                            continue;
                        }
                        db.call("VM.recover", vm, sessionTo, false);
                        recoveredVms.add(r.uuid);
                        System.out.println("  recovered " + r.nameLabel);
                    }
                    db.call("session.logout");
                }
            }

            // The recovered VMs keep their uuids, so look them up by uuid - a name may be taken here already.
            for (String uuid : recoveredVms) {
                VM vm = VM.getByUuid(conn, uuid);
                System.out.println(vm.getNameLabel(conn) + " is " + vm.getPowerState(conn));
            }

            if (testFailover) {
                for (String uuid : recoveredVms) {
                    VM vm = VM.getByUuid(conn, uuid);
                    if (vm.getPowerState(conn) != Types.VmPowerState.HALTED) vm.hardShutdown(conn);
                    vm.destroy(conn);
                }
                for (String uuid : recoveredVapps) VMAppliance.getByUuid(conn, uuid).destroy(conn);
            }
            // Destroying the task detaches and forgets the SRs it attached that no recovered VM needs.
            task.destroy(conn);
            if (testFailover) {
                // The SRs the recovered VMs needed are no longer the task's: detach and forget those too.
                for (SR sr : introduced) {
                    try {
                        for (PBD pbd : sr.getPBDs(conn))
                            if (pbd.getCurrentlyAttached(conn)) pbd.unplug(conn);
                        sr.forget(conn);
                    } catch (Types.HandleInvalid alreadyForgotten) {
                        // forgotten by DR_task.destroy
                    }
                }
                System.out.println("Test failover: removed the recovered VMs and detached the replica");
            } else {
                System.out.println("Recovered VMs are halted: start them when you are ready");
            }
            System.out.println("OK: disaster-recovery-failover");
        } finally {
            Session.logout(conn);
        }
    }

    /**
     * Calls on a database session from VDI.open_database. The generated classes always send the
     * Connection's own session, so these dispatch by hand with the database session in its place, over the
     * same Connection (and its HTTP client, which accepts the host's certificate).
     */
    private static final class Database {
        private final Connection conn;
        private final String session;

        Database(Connection conn, Session session) {
            this.conn = conn;
            this.session = session.toWireString();
        }

        <T> T call(String method, TypeReference<T> type, Object... args) throws Exception {
            return conn.dispatch(method, withSession(args), type);
        }

        void call(String method, Object... args) throws Exception {
            conn.dispatch(method, withSession(args));
        }

        private Object[] withSession(Object[] args) {
            Object[] all = new Object[args.length + 1];
            all[0] = session;
            System.arraycopy(args, 0, all, 1, args.length);
            return all;
        }
    }

    /** The error: a typed exception's name (VmRequiresSr, ...), else the XenAPI error code. */
    private static String code(Types.XenAPIException e) {
        if (e.getClass() != Types.XenAPIException.class) return e.getClass().getSimpleName();
        return e.errorDescription != null && e.errorDescription.length > 0 ? e.errorDescription[0] : e.toString();
    }
}
```

<details><summary>Example output</summary>

```text
Found SR DR storage (000003e9-0000-0000-0600-000000000000), with pool metadata
Attached DR storage
  pool metadata of protected-pool
  recovered app-01
  cannot recover db-01: VmRequiresSr
app-01 is Halted
Test failover: removed the recovered VMs and detached the replica
OK: disaster-recovery-failover
```

</details>

## Go

Source: [`go/disaster_recovery_failover.go`](../../go/disaster_recovery_failover.go)

```go
package main

import (
	"encoding/json"
	"encoding/xml"
	"fmt"
	"sort"
	"strings"

	"go/xenapi"
)

// disasterRecoveryFailover - Fail over to the disaster recovery site.
//
// On the pool at the disaster recovery site, attach the storage array's replica of the protected pool's
// storage, read the pool metadata replicated to it, and recover the VMs and vApps it describes. By
// default this is a test failover, which removes what it recovered and detaches the storage again.
//
// The replica is the LUN the storage array mirrors the protected pool's SR to: name it by the iSCSI
// target, IQN and SCSI id (srType "lvmoiscsi"), or by SCSI id alone for Fibre Channel/SAS (srType
// "lvmohba"). Before a real failover, break the mirror so that this site can write to the replica, and
// make sure no other pool has those LUNs attached: two pools using the same LUN corrupt it.
//
// DR_task.create attaches every SR on the LUN that you name (by uuid) to this pool, keeping its uuid, and
// VDI.open_database gives a session onto the metadata replicated there - a separate, read-only database,
// not this pool. Recovering runs on that session and names this pool's session as the place to recover
// into. A test failover then removes the recovered VMs and vApps - not their disks, which are the
// replica's - and detaches and forgets the SRs, as the wizard does.
//
// Run it:
//
//	disasterRecoveryFailover("https://dr-site-pool", "root", password, "192.0.2.31",
//		"iqn.2009-01.com.example:replica-0", "360a98...", "", "lvmoiscsi", true)
func disasterRecoveryFailover(url, user, password, target, targetIQN, scsiID, port, srType string, testFailover bool) {
	session := connect(url, user, password)
	defer session.Logout()

	deviceConfig := map[string]string{"SCSIid": scsiID}
	if srType == "lvmoiscsi" {
		deviceConfig["target"] = target
		deviceConfig["targetIQN"] = targetIQN
		if port != "" {
			deviceConfig["port"] = port
		}
	}

	// Which SRs are on the LUN, and which of them hold pool metadata. sm_config metadata=true asks for
	// their names and the pool_metadata_detected flag as well as their uuids.
	pools, err := xenapi.Pool.GetAll(session)
	check(err)
	master, err := xenapi.Pool.GetMaster(session, pools[0])
	check(err)
	probe, err := xenapi.SR.Probe(session, master, deviceConfig, srType, map[string]string{"metadata": "true"})
	check(err)
	var found struct {
		SRs []struct {
			UUID         string `xml:"UUID"`
			NameLabel    string `xml:"name_label"`
			PoolMetadata string `xml:"pool_metadata_detected"`
		} `xml:"SR"`
	}
	check(xml.Unmarshal([]byte(probe), &found))
	var uuids []string
	for _, sr := range found.SRs {
		uuid := strings.TrimSpace(sr.UUID)
		withMetadata := ""
		if strings.TrimSpace(sr.PoolMetadata) == "true" {
			withMetadata = ", with pool metadata"
		}
		fmt.Printf("Found SR %s (%s)%s\n", strings.TrimSpace(sr.NameLabel), uuid, withMetadata)
		uuids = append(uuids, uuid)
	}
	if len(uuids) == 0 {
		panic("there is no SR on that LUN")
	}

	task, err := xenapi.DRTask.Create(session, srType, deviceConfig, uuids)
	check(err)
	introduced, err := xenapi.DRTask.GetIntroducedSRs(session, task)
	check(err)
	var attached []string
	for _, sr := range introduced {
		name, err := xenapi.SR.GetNameLabel(session, sr)
		check(err)
		attached = append(attached, name)
	}
	fmt.Printf("Attached %s\n", strings.Join(attached, ", "))

	// The Go binding cannot make calls on a session it did not log in itself, so the calls on the
	// replicated database go over plain JSON-RPC (see rawRPCCall). For the same reason it cannot hand over
	// its own session id, so session_to - this pool, where the VMs are to land - is a second login here.
	sessionTo := rawLogin(url, user, password)
	defer rawRPCCall(url, "session.logout", sessionTo)

	// Recover from every replicated database on the attached SRs: vApps first (their VMs come with them),
	// then the VMs not in a vApp. A VM whose disks are on storage this pool hasn't attached can't be
	// recovered - assert_can_be_recovered says so (VM_REQUIRES_SR) - so skip it.
	var recoveredVMs, recoveredVApps []string
	for _, sr := range introduced {
		vdis, err := xenapi.SR.GetVDIs(session, sr)
		check(err)
		for _, vdi := range vdis {
			t, err := xenapi.VDI.GetType(session, vdi)
			check(err)
			latest, err := xenapi.VDI.GetMetadataLatest(session, vdi)
			check(err)
			if t != xenapi.VdiTypeMetadata || !latest {
				continue
			}
			ref, err := xenapi.VDI.OpenDatabase(session, vdi)
			check(err)
			database := string(ref)

			// A pool often has no name of its own; show its coordinator's name instead.
			var poolRecords map[string]struct {
				NameLabel string `json:"name_label"`
				Master    string `json:"master"`
			}
			check(json.Unmarshal(rawRPC(url, "pool.get_all_records", database), &poolRecords))
			for _, pool := range poolRecords {
				name := pool.NameLabel
				if name == "" {
					check(json.Unmarshal(rawRPC(url, "host.get_name_label", database, pool.Master), &name))
				}
				fmt.Printf("  pool metadata of %s\n", name)
			}

			inRecoveredVApp := map[string]bool{}
			var vapps map[string]struct {
				UUID      string   `json:"uuid"`
				NameLabel string   `json:"name_label"`
				VMs       []string `json:"VMs"`
			}
			check(json.Unmarshal(rawRPC(url, "VM_appliance.get_all_records", database), &vapps))
			for vapp, r := range vapps {
				if _, failure := rawRPCCall(url, "VM_appliance.assert_can_be_recovered", database, vapp, sessionTo); failure != nil {
					fmt.Printf("  cannot recover vApp %s: %s\n", r.NameLabel, rawFailureCode(failure))
					continue
				}
				rawRPC(url, "VM_appliance.recover", database, vapp, sessionTo, false)
				recoveredVApps = append(recoveredVApps, r.UUID)
				for _, vm := range r.VMs {
					var uuid string
					check(json.Unmarshal(rawRPC(url, "VM.get_uuid", database, vm), &uuid))
					recoveredVMs = append(recoveredVMs, uuid)
					inRecoveredVApp[vm] = true
				}
				fmt.Printf("  recovered vApp %s\n", r.NameLabel)
			}

			var vms map[string]struct {
				UUID            string `json:"uuid"`
				NameLabel       string `json:"name_label"`
				IsATemplate     bool   `json:"is_a_template"`
				IsControlDomain bool   `json:"is_control_domain"`
				IsASnapshot     bool   `json:"is_a_snapshot"`
			}
			check(json.Unmarshal(rawRPC(url, "VM.get_all_records", database), &vms))
			refs := make([]string, 0, len(vms))
			for vm := range vms {
				refs = append(refs, vm)
			}
			sort.Slice(refs, func(i, j int) bool { return vms[refs[i]].NameLabel < vms[refs[j]].NameLabel })
			for _, vm := range refs {
				r := vms[vm]
				if r.IsATemplate || r.IsControlDomain || r.IsASnapshot || inRecoveredVApp[vm] {
					continue
				}
				if _, failure := rawRPCCall(url, "VM.assert_can_be_recovered", database, vm, sessionTo); failure != nil {
					fmt.Printf("  cannot recover %s: %s\n", r.NameLabel, rawFailureCode(failure))
					continue
				}
				rawRPC(url, "VM.recover", database, vm, sessionTo, false)
				recoveredVMs = append(recoveredVMs, r.UUID)
				fmt.Printf("  recovered %s\n", r.NameLabel)
			}
			rawRPC(url, "session.logout", database)
		}
	}

	// The recovered VMs keep their uuids, so look them up by uuid - a name may be taken here already.
	for _, uuid := range recoveredVMs {
		vm, err := xenapi.VM.GetByUUID(session, uuid)
		check(err)
		name, err := xenapi.VM.GetNameLabel(session, vm)
		check(err)
		state, err := xenapi.VM.GetPowerState(session, vm)
		check(err)
		fmt.Printf("%s is %s\n", name, state)
	}

	if testFailover {
		for _, uuid := range recoveredVMs {
			vm, err := xenapi.VM.GetByUUID(session, uuid)
			check(err)
			if state, err := xenapi.VM.GetPowerState(session, vm); err == nil && state != xenapi.VMPowerStateHalted {
				check(xenapi.VM.HardShutdown(session, vm))
			}
			check(xenapi.VM.Destroy(session, vm))
		}
		for _, uuid := range recoveredVApps {
			vapp, err := xenapi.VMAppliance.GetByUUID(session, uuid)
			check(err)
			check(xenapi.VMAppliance.Destroy(session, vapp))
		}
	}
	// Destroying the task detaches and forgets the SRs it attached that no recovered VM needs.
	check(xenapi.DRTask.Destroy(session, task))
	if testFailover {
		// The SRs the recovered VMs needed are no longer the task's: detach and forget those too.
		for _, sr := range introduced {
			pbds, err := xenapi.SR.GetPBDs(session, sr)
			if err != nil && failureCode(err) == xenapi.ErrorHandleInvalid {
				continue // forgotten by DR_task.destroy
			}
			check(err)
			for _, pbd := range pbds {
				if attached, err := xenapi.PBD.GetCurrentlyAttached(session, pbd); err == nil && attached {
					check(xenapi.PBD.Unplug(session, pbd))
				}
			}
			check(xenapi.SR.Forget(session, sr))
		}
		fmt.Println("Test failover: removed the recovered VMs and detached the replica")
	} else {
		fmt.Println("Recovered VMs are halted: start them when you are ready")
	}
	fmt.Println("OK: disaster-recovery-failover")
}

// rawFailureCode is the XenAPI error code in a JSON-RPC error (its message).
func rawFailureCode(failure json.RawMessage) string {
	var e struct {
		Message string `json:"message"`
	}
	if json.Unmarshal(failure, &e) == nil && e.Message != "" {
		return e.Message
	}
	return string(failure)
}
```

<details><summary>Example output</summary>

```text
Found SR DR storage (000003e9-0000-0000-0600-000000000000), with pool metadata
Attached DR storage
  pool metadata of protected-pool
  recovered app-01
  cannot recover db-01: VM_REQUIRES_SR
app-01 is Halted
Test failover: removed the recovered VMs and detached the replica
OK: disaster-recovery-failover
```

</details>

## PowerShell

Source: [`powershell/DisasterRecovery/Invoke-DisasterRecoveryFailover.ps1`](../../powershell/DisasterRecovery/Invoke-DisasterRecoveryFailover.ps1)

```powershell
function Invoke-DisasterRecoveryFailover {
    <#
    .SYNOPSIS
        Fail over to the disaster recovery site.
    .DESCRIPTION
        On the pool at the disaster recovery site, attach the storage array's replica of the protected pool's
        storage, read the pool metadata replicated to it, and recover the VMs and vApps it describes. By
        default this is a test failover, which removes what it recovered and detaches the storage again.
    .EXAMPLE
        Invoke-DisasterRecoveryFailover -Url https://dr-site-pool -UserName root -Password $password `
            -Target 192.0.2.31 -TargetIqn iqn.2009-01.com.example:replica-0 -ScsiId 360a98...
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password,
        [string]$Target,
        [string]$TargetIqn,
        [Parameter(Mandatory = $true)][string]$ScsiId,
        [string]$Port,
        [string]$SrType = 'lvmoiscsi',
        [bool]$TestFailover = $true
    )
    # The replica is the LUN the storage array mirrors the protected pool's SR to: name it by the iSCSI
    # target, IQN and SCSI id (SrType lvmoiscsi), or by SCSI id alone for Fibre Channel/SAS (SrType
    # lvmohba). Before a real failover, break the mirror so that this site can write to the replica, and
    # make sure no other pool has those LUNs attached: two pools using the same LUN corrupt it.
    #
    # DR_task.create attaches every SR on the LUN that you name (by uuid) to this pool, keeping its uuid,
    # and VDI.open_database gives a session onto the metadata replicated there - a separate, read-only
    # database, not this pool. Recovering runs on that session and names this pool's session as the place
    # to recover into. A test failover then removes the recovered VMs and vApps - not their disks, which
    # are the replica's - and detaches and forgets the SRs, as the wizard does.
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password

    $deviceConfig = @{ SCSIid = $ScsiId }
    if ($SrType -eq 'lvmoiscsi') {
        $deviceConfig.target = $Target
        $deviceConfig.targetIQN = $TargetIqn
        if ($Port) { $deviceConfig.port = $Port }
    }

    # Which SRs are on the LUN, and which of them hold pool metadata. sm_config metadata=true asks for
    # their names and the pool_metadata_detected flag as well as their uuids. (SR.probe is a static call:
    # the host goes in -XenHost, and -Ref, which the cmdlet insists on, is ignored.)
    $master = (Get-XenPool).master.opaque_ref
    $probe = Invoke-XenSR -Ref "OpaqueRef:NULL" -XenAction Probe -XenHost $master -DeviceConfig $deviceConfig `
        -Type $SrType -SmConfig @{ metadata = 'true' } -PassThru
    $srs = @(([xml]$probe).SelectNodes('/SRlist/SR'))
    foreach ($found in $srs) {
        $withMetadata = if ("$($found.pool_metadata_detected)".Trim() -eq 'true') { ", with pool metadata" } else { "" }
        Write-Host "Found SR $("$($found.name_label)".Trim()) ($("$($found.UUID)".Trim()))$withMetadata"
    }
    if ($srs.Count -eq 0) { throw "there is no SR on that LUN" }

    $task = New-XenDRTask -Type $SrType -DeviceConfig $deviceConfig `
        -Whitelist @($srs | ForEach-Object { "$($_.UUID)".Trim() }) -PassThru
    $introduced = @($task.introduced_SRs | ForEach-Object { Get-XenSR -Ref $_.opaque_ref })
    Write-Host "Attached $(($introduced | ForEach-Object { $_.name_label }) -join ', ')"

    # Recover from every replicated database on the attached SRs: vApps first (their VMs come with them),
    # then the VMs not in a vApp. A VM whose disks are on storage this pool hasn't attached can't be
    # recovered - assert_can_be_recovered says so (VM_REQUIRES_SR) - so skip it.
    #
    # The module's cmdlets only take sessions they created themselves, so the calls on the replicated
    # database go over JSON-RPC (Invoke-XenMethod, in Helpers.ps1).
    $recoveredVms = @()
    $recoveredVapps = @()
    foreach ($sr in $introduced) {
        $vdis = Get-XenVDI | Where-Object {
            $_.SR.opaque_ref -eq $sr.opaque_ref -and $_.type -eq 'metadata' -and $_.metadata_latest
        }
        foreach ($vdi in $vdis) {
            $databaseRef = Invoke-XenMethod -Session $session -Method 'VDI.open_database' -Params @($vdi.opaque_ref)
            $database = [pscustomobject]@{ opaque_ref = $databaseRef; Url = $session.Url }

            # A pool often has no name of its own; show its coordinator's name instead.
            $pool = (Invoke-XenMethod -Session $database -Method 'pool.get_all_records').PSObject.Properties |
                Select-Object -First 1
            $poolName = $pool.Value.name_label
            if (-not $poolName) {
                $poolName = Invoke-XenMethod -Session $database -Method 'host.get_name_label' -Params @($pool.Value.master)
            }
            Write-Host "  pool metadata of $poolName"

            $inRecoveredVapp = @{}
            $vapps = (Invoke-XenMethod -Session $database -Method 'VM_appliance.get_all_records').PSObject.Properties
            foreach ($vapp in $vapps) {
                try {
                    Invoke-XenMethod -Session $database -Method 'VM_appliance.assert_can_be_recovered' `
                        -Params @($vapp.Name, $session.opaque_ref) | Out-Null
                }
                catch {
                    Write-Host "  cannot recover vApp $($vapp.Value.name_label): $(Get-FailureCode $_)"
                    continue
                }
                Invoke-XenMethod -Session $database -Method 'VM_appliance.recover' `
                    -Params @($vapp.Name, $session.opaque_ref, $false) | Out-Null
                $recoveredVapps += $vapp.Value.uuid
                foreach ($vm in $vapp.Value.VMs) {
                    $recoveredVms += Invoke-XenMethod -Session $database -Method 'VM.get_uuid' -Params @($vm)
                    $inRecoveredVapp[$vm] = $true
                }
                Write-Host "  recovered vApp $($vapp.Value.name_label)"
            }

            $vms = (Invoke-XenMethod -Session $database -Method 'VM.get_all_records').PSObject.Properties |
                Sort-Object { $_.Value.name_label }
            foreach ($vm in $vms) {
                $r = $vm.Value
                if ($r.is_a_template -or $r.is_control_domain -or $r.is_a_snapshot -or $inRecoveredVapp[$vm.Name]) {
                    continue
                }
                try {
                    Invoke-XenMethod -Session $database -Method 'VM.assert_can_be_recovered' `
                        -Params @($vm.Name, $session.opaque_ref) | Out-Null
                }
                catch {
                    Write-Host "  cannot recover $($r.name_label): $(Get-FailureCode $_)"
                    continue
                }
                Invoke-XenMethod -Session $database -Method 'VM.recover' `
                    -Params @($vm.Name, $session.opaque_ref, $false) | Out-Null
                $recoveredVms += $r.uuid
                Write-Host "  recovered $($r.name_label)"
            }
            Invoke-XenMethod -Session $database -Method 'session.logout' | Out-Null
        }
    }

    # The recovered VMs keep their uuids, so look them up by uuid - a name may be taken here already.
    foreach ($uuid in $recoveredVms) {
        $vm = Get-XenVM -Uuid $uuid
        Write-Host "$($vm.name_label) is $($vm.power_state)"
    }

    if ($TestFailover) {
        foreach ($uuid in $recoveredVms) {
            $vm = Get-XenVM -Uuid $uuid
            if ($vm.power_state -ne 'Halted') { $vm | Invoke-XenVM -XenAction HardShutdown }
            $vm | Remove-XenVM
        }
        foreach ($uuid in $recoveredVapps) { Get-XenVMAppliance -Uuid $uuid | Remove-XenVMAppliance }
    }
    # Destroying the task detaches and forgets the SRs it attached that no recovered VM needs.
    $task | Remove-XenDRTask
    if ($TestFailover) {
        # The SRs the recovered VMs needed are no longer the task's: detach and forget those too.
        foreach ($sr in $introduced) {
            if (Get-XenSR -Uuid $sr.uuid -ErrorAction SilentlyContinue) {
                Invoke-DetachAndForgetSr -Ref $sr.opaque_ref
            }
        }
        Write-Host "Test failover: removed the recovered VMs and detached the replica"
    }
    else {
        Write-Host "Recovered VMs are halted: start them when you are ready"
    }
    Write-Host "OK: disaster-recovery-failover"
    $session | Disconnect-XenServer
}

function Get-FailureCode {
    <#
    .SYNOPSIS
        The XenAPI error code in a failed Invoke-XenMethod call.
    #>
    param($ErrorRecord)
    if ("$ErrorRecord" -match '"message":"([A-Z0-9_]+)"') { return $Matches[1] }
    return "$ErrorRecord"
}
```

<details><summary>Example output</summary>

```text
Found SR DR storage (000003e9-0000-0000-0600-000000000000), with pool metadata
Attached DR storage
  pool metadata of protected-pool
  recovered app-01
  cannot recover db-01: VM_REQUIRES_SR
app-01 is Halted
Test failover: removed the recovered VMs and detached the replica
OK: disaster-recovery-failover
```

</details>

## xe CLI

Source: [`cli/disaster-recovery/disaster-recovery-failover.sh`](../../cli/disaster-recovery/disaster-recovery-failover.sh)

```bash
# Fail over to the disaster recovery site.
#
# On the pool at the disaster recovery site, attach the storage array's replica of the protected pool's
# storage, read the pool metadata replicated to it, and recover the VMs and vApps it describes. By
# default this is a test failover, which removes what it recovered and detaches the storage again.
#
# Run it:
#   ./workflows.sh disaster-recovery-failover https://dr-site-pool root "$password" \
#       target=192.0.2.31 target_iqn=iqn.2009-01.com.example:replica-0 scsi_id=360a98...
#
# Optional key=value arguments (default):
#   target (192.0.2.31)
#   target_iqn (iqn.2009-01.com.example:replica-0)
#   scsi_id (360a980004265656d5f4a2d63764e5738)
#   port ("")
#   sr_type (lvmoiscsi)
#   test_failover (true)

# The replica is the LUN the storage array mirrors the protected pool's SR to: name it by the iSCSI target,
# IQN and SCSI id (sr_type lvmoiscsi), or by SCSI id alone for Fibre Channel/SAS (sr_type lvmohba). Before a
# real failover, break the mirror so that this site can write to the replica, and make sure no other pool
# has those LUNs attached: two pools using the same LUN corrupt it.
#
# drtask-create attaches every SR on the LUN that you name (by uuid) to this pool, keeping its uuid. The
# database: option (database:vdi-uuid=<metadata disk>) runs a command against the metadata replicated there
# - a separate, read-only database - instead of this pool, and vm-recover/appliance-recover recover out of
# it into this pool. A test failover then removes the recovered VMs and vApps - not their disks, which are
# the replica's - and detaches and forgets the SRs, as the wizard does.
disaster_recovery_failover() {
    local sr_type test_failover task sr vdi line uuid name has_metadata pool_name master vapp vm reason
    local -a dc uuids=() introduced=() recovered_vms=() recovered_vapps=() in_recovered_vapp=()
    sr_type=$(param sr_type lvmoiscsi)
    test_failover=$(param test_failover true)
    dc=(device-config:SCSIid=$(param scsi_id 360a980004265656d5f4a2d63764e5738))
    if [ "$sr_type" = lvmoiscsi ]; then
        dc+=(device-config:target=$(param target 192.0.2.31)
             device-config:targetIQN=$(param target_iqn iqn.2009-01.com.example:replica-0))
        [ -z "$(param port "")" ] || dc+=(device-config:port=$(param port ""))
    fi

    # Which SRs are on the LUN, and which of them hold pool metadata. sm-config:metadata=true asks for their
    # names and the pool_metadata_detected flag as well as their uuids. The probe answers one tag per line.
    uuid=""
    while IFS= read -r line; do
        case "$line" in
            *"<UUID>"*) uuid=$(xml_tag_text "$line" UUID); name=""; has_metadata="" ;;
            *"<name_label>"*) name=$(xml_tag_text "$line" name_label) ;;
            *"<pool_metadata_detected>true"*) has_metadata=", with pool metadata" ;;
            *"</SR>"*)
                echo "Found SR $name ($uuid)$has_metadata"
                uuids+=("$uuid") ;;
        esac
    done <<< "$(xe sr-probe type=$sr_type "${dc[@]}" sm-config:metadata=true)"
    if [ ${#uuids[@]} -eq 0 ]; then
        echo "there is no SR on that LUN" >&2
        exit 1
    fi

    task=$(xe drtask-create type=$sr_type "${dc[@]}" sr-whitelist=$(IFS=,; echo "${uuids[*]}"))
    for sr in $(each_csv "$(set_to_csv "$(xe drtask-param-get uuid=$task param-name=introduced-SRs)")"); do
        introduced+=("$sr")
    done
    echo "Attached $(for sr in "${introduced[@]}"; do xe sr-param-get uuid=$sr param-name=name-label; done | paste -sd, - | sed 's/,/, /g')"

    # Recover from every replicated database on the attached SRs: vApps first (their VMs come with them),
    # then the VMs not in a vApp. A VM whose disks are on storage this pool hasn't attached can't be
    # recovered - vm-assert-can-be-recovered says so - so skip it.
    for sr in "${introduced[@]}"; do
        for vdi in $(each_csv "$(xe vdi-list sr-uuid=$sr metadata-latest=true --minimal)"); do
            t=$(xe vdi-param-get uuid=$vdi param-name=type)
            [ "${t,,}" = metadata ] || continue
            db=database:vdi-uuid=$vdi

            # A pool often has no name of its own; show its coordinator's name instead.
            pool_name=$(xe pool-list $db params=name-label --minimal)
            if [ -z "$pool_name" ]; then
                master=$(xe pool-list $db params=master --minimal)
                pool_name=$(xe host-list $db uuid=$master params=name-label --minimal)
            fi
            echo "  pool metadata of $pool_name"

            in_recovered_vapp=()
            for vapp in $(each_csv "$(xe appliance-list $db --minimal)"); do
                name=$(xe appliance-list $db uuid=$vapp params=name-label --minimal)
                if ! reason=$(xe appliance-assert-can-be-recovered uuid=$vapp $db 2>&1); then
                    echo "  cannot recover vApp $name: ${reason%%$'\n'*}"
                    continue
                fi
                xe appliance-recover uuid=$vapp $db
                recovered_vapps+=("$vapp")
                for vm in $(each_csv "$(set_to_csv "$(xe appliance-list $db uuid=$vapp params=VMs --minimal)")"); do
                    recovered_vms+=("$vm"); in_recovered_vapp+=("$vm")
                done
                echo "  recovered vApp $name"
            done

            while IFS=$'\t' read -r name vm; do
                [ -n "$vm" ] || continue
                [[ " ${in_recovered_vapp[*]} " == *" $vm "* ]] && continue
                if ! reason=$(xe vm-assert-can-be-recovered uuid=$vm $db 2>&1); then
                    echo "  cannot recover $name: ${reason%%$'\n'*}"
                    continue
                fi
                xe vm-recover uuid=$vm $db
                recovered_vms+=("$vm")
                echo "  recovered $name"
            done <<< "$(for vm in $(each_csv "$(xe vm-list $db is-a-template=false is-control-domain=false \
                            is-a-snapshot=false --minimal)"); do
                            printf '%s\t%s\n' "$(xe vm-list $db uuid=$vm params=name-label --minimal)" "$vm"
                        done | sort)"
        done
    done

    # The recovered VMs keep their uuids, so look them up by uuid - a name may be taken here already.
    for vm in "${recovered_vms[@]}"; do
        echo "$(xe vm-param-get uuid=$vm param-name=name-label) is $(xe vm-param-get uuid=$vm param-name=power-state)"
    done

    if [ "$test_failover" = true ]; then
        for vm in "${recovered_vms[@]}"; do
            [ "$(xe vm-param-get uuid=$vm param-name=power-state)" = halted ] || xe vm-shutdown uuid=$vm force=true
            xe vm-destroy uuid=$vm
        done
        for vapp in "${recovered_vapps[@]}"; do xe appliance-destroy uuid=$vapp; done
    fi
    # Destroying the task detaches and forgets the SRs it attached that no recovered VM needs.
    xe drtask-destroy uuid=$task
    if [ "$test_failover" = true ]; then
        # The SRs the recovered VMs needed are no longer the task's: detach and forget those too.
        for sr in "${introduced[@]}"; do
            [ -z "$(xe sr-list uuid=$sr --minimal)" ] || detach_and_forget_sr $sr
        done
        echo "Test failover: removed the recovered VMs and detached the replica"
    else
        echo "Recovered VMs are halted: start them when you are ready"
    fi
    echo "OK: disaster-recovery-failover"
}
```

<details><summary>Example output</summary>

```text
Found SR DR storage (000003e9-0000-0000-0600-000000000000), with pool metadata
Attached DR storage
  pool metadata of protected-pool
  recovered app-01
  cannot recover db-01: You attempted to run a VM on a host which doesn't have access to an SR needed by the VM. The VM has at least one VBD attached to a VDI in the SR.
app-01 is halted
Test failover: removed the recovered VMs and detached the replica
OK: disaster-recovery-failover
```

</details>
