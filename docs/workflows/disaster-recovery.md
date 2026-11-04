<!-- Generated from workflows.json, the example sources and a run of each example. Edit those, not this file. -->

# Recover VMs after a disaster

Replicate the pool's database to shared storage, read it back as a separate database to see what it describes, and recover a VM out of it into a second, standby pool (dr_url).

**Requires:** a second pool that can reach the same storage.

Workflow `disaster-recovery`. [All workflows](README.md) · [Connecting](connecting.md)

## C# (.NET)

Source: [`csharp/DisasterRecovery/DisasterRecovery.cs`](../../csharp/DisasterRecovery/DisasterRecovery.cs)

```csharp
/// <summary>
/// Replicate the pool's database to shared storage, read it back as a separate database to see what it
/// describes, and recover a VM out of it into a second, standby pool (dr_url).
/// </summary>
/// <example>
/// <code>
/// Workflows.DisasterRecovery("https://xenserver", "root", password, "https://standby-pool");
/// </code>
/// </example>
/// <remarks>
/// Replicate the pool's database to shared storage, then recover a VM out of it onto a second, standby
/// pool. That destination has to be a DIFFERENT, standby pool: recovering a VM back into the exact pool
/// it was replicated from can't actually succeed with force=false (VM_TO_IMPORT_IS_NOT_NEWER_VERSION),
/// and passing force=true instead would succeed by REPLACING the live original - exactly the opposite of
/// what a DR demo should show, and the thing that would actually destroy a live VM if ever pointed at the
/// same pool it replicated from. Track the recovered VM by uuid, never by name: a name can coincidentally
/// collide with something already on the destination pool.
/// </remarks>
public static void DisasterRecovery(string url, string user, string password, string drUrl)
{
    if (string.IsNullOrEmpty(drUrl))
        throw new Exception("disaster-recovery needs a second pool to recover into: pass " +
                            "dr_url=<url of a standby pool>");

    var session = Connect(url, user, password);
    var drSession = Connect(drUrl, user, password);

    // Replication needs shared storage the standby pool can attach too, and only block storage (iSCSI,
    // HBA) supports it - an NFS SR fails SR_OPERATION_NOT_SUPPORTED. The server checks rather than
    // taking your word for it, so ask each candidate, as XenCenter's DR wizard does.
    static bool Succeeds(Action call)
    {
        try { call(); return true; }
        catch (Failure) { return false; }
    }
    var sr = SR.get_all_records(session).FirstOrDefault(kv =>
        kv.Value.shared && kv.Value.content_type != "iso"
        && Succeeds(() => SR.assert_supports_database_replication(session, kv.Key.opaque_ref))).Key?.opaque_ref
        ?? throw new Exception("no shared SR here supports database replication (it needs iSCSI or HBA storage)");
    Console.WriteLine($"Replicating pool metadata to {SR.get_name_label(session, sr)}");
    SR.enable_database_replication(session, sr);

    // Everything from here happens on the STANDBY pool, the way XenCenter's DR wizard works from the
    // pool you fail over to: it has the same SR attached, rescans it to see the metadata disk just
    // written, opens the database there, and recovers into itself - VM.recover's session_to has to be
    // a session of the server running the call (HANDLE_INVALID otherwise).
    string drSr;
    try { drSr = SR.get_by_uuid(drSession, SR.get_uuid(session, sr)).opaque_ref; }
    catch (Failure)
    {
        throw new Exception($"the standby pool has not attached {SR.get_name_label(session, sr)}: " +
                            "attach the same storage there first");
    }
    SR.scan(drSession, drSr);
    var vdi = SR.get_VDIs(drSession, drSr)
        .First(v => VDI.get_type(drSession, v.opaque_ref) == vdi_type.metadata).opaque_ref;
    Console.WriteLine($"  metadata disk: {VDI.get_uuid(drSession, vdi)}");

    // A session onto the replicated database rather than the live pool. Assembled from the URL and the
    // session id we were handed rather than with Session(url, opaqueRef): that constructor queries the
    // pool immediately to work out the API version, which happens before there is any chance to accept
    // the host's self-signed certificate.
    var metadata = new Session(drUrl) { opaque_ref = VDI.open_database(drSession, vdi).opaque_ref };
    metadata.JsonRpcClient.ServerCertificateValidationCallback = (req, cert, chain, errors) => true;

    // Only real guest VMs are recoverable - exclude templates, control domains and snapshots.
    var recoverable = VM.get_all_records(metadata).Where(kv =>
        !kv.Value.is_a_template && !kv.Value.is_control_domain && !kv.Value.is_a_snapshot).ToList();
    Console.WriteLine($"  the replicated database describes {recoverable.Count} recoverable VM(s)");

    // Only a VM whose disks are all on storage the standby pool can see can be recovered there - the
    // check runs on the METADATA session, and session_to says where the VM should land: the STANDBY
    // pool's session, not this one. Take the first (by name) that passes, as the DR wizard lists them.
    var candidates = recoverable.OrderBy(kv => kv.Value.name_label)
        .Where(kv => Succeeds(() => VM.assert_can_be_recovered(metadata, kv.Key.opaque_ref, drSession.opaque_ref)))
        .ToList();
    if (candidates.Count == 0)
        throw new Exception("no VM in the replicated database has all its disks on storage the standby pool can see");
    var target = candidates[0];
    var targetUuid = target.Value.uuid;
    var name = target.Value.name_label;
    Console.WriteLine($"  recovering {name}");
    VM.recover(metadata, target.Key.opaque_ref, drSession.opaque_ref, false);

    // It is a real VM on the standby pool now, not merely a call that returned - look it up by the
    // uuid full_restore preserved, not by name. NO fallback to the source pool: a second pool is the
    // only correct target, and on a real pool this lookup always succeeds.
    var recovered = VM.get_by_uuid(drSession, targetUuid).opaque_ref;
    Console.WriteLine($"  {name} is {VM.get_power_state(drSession, recovered)} on the standby pool");

    // Tidy up on the standby pool only, by uuid - never touch the source pool's VMs, and never
    // guess by name. Destroy the VM record but NOT its disks: they are the protected pool's own
    // disks on the shared SR, not copies.
    VM.destroy(drSession, recovered);
    SR.disable_database_replication(session, sr);
    Console.WriteLine("OK: disaster-recovery");
    session.logout();
    drSession.logout();
}
```

<details><summary>Sample output</summary>

```text
Replicating pool metadata to Shared NFS
  metadata disk: 00000001-0000-0000-8d01-000000000000
  the replicated database describes 6 recoverable VM(s)
  recovering cache-01 (recovered)
  cache-01 (recovered) is Halted in the live pool
OK: disaster-recovery
```

</details>

## Python

Source: [`python/disaster_recovery/disaster_recovery.py`](../../python/disaster_recovery/disaster_recovery.py)

```python
"""Recover VMs after a disaster.

Replicate the pool's database to shared storage, read it back as a separate database to see what it
describes, and recover a VM out of it into a second, standby pool (dr_url).

Run it::

    disaster_recovery("https://xenserver", "root", password, dr_url="https://standby-pool")
"""

import XenAPI

from connection import connect


def disaster_recovery(url, username, password, dr_url=None):
    """Replicate the pool's database to shared storage, then recover a VM out of it onto a second,
    standby pool.

    Disaster recovery works by writing the pool's own database out to a storage repository
    as a disk of type "metadata". That disk can be read back as a SEPARATE database --
    VDI.open_database hands you a session scoped to it -- so the ordinary calls describe
    the pool as it was replicated rather than the pool you are connected to. Recovering
    reads from that database and writes into a live pool, which is why the recover call
    is made on the metadata session and takes a live session as its destination.

    That destination has to be a DIFFERENT, standby pool: recovering a VM back into the exact
    pool it was replicated from can't actually succeed with force=False. The VM's uuid already
    exists there, so VM.recover always takes the replace-or-fail path, and nothing replicated a
    moment ago from a live database can ever be "newer" than the live object it came from - it
    fails with VM_TO_IMPORT_IS_NOT_NEWER_VERSION. The one-line "fix" of passing force=True instead
    would make it succeed by REPLACING (destroying and recreating) the live original - exactly the
    opposite of what a DR demo should show. A second pool is the only way force=False succeeds (a
    brand-new VM object, not a replace), and it's what every real DR workflow actually does.
    Track the recovered VM by uuid, never by name: a name can coincidentally collide with
    something already on the destination pool, and tidy-up must never guess by name."""
    if not dr_url:
        raise RuntimeError("disaster-recovery needs a second pool to recover into: pass "
                            "dr_url=<url of a standby pool>")
    session = connect(url, username, password)
    dr_session = connect(dr_url, username, password)
    x = session.xenapi

    # Replication needs shared storage the standby pool can attach too, and only block storage (iSCSI,
    # HBA) supports it - an NFS SR fails SR_OPERATION_NOT_SUPPORTED. The server checks rather than taking
    # your word for it, so ask each candidate, as XenCenter's DR wizard does.
    def supports_replication(sr):
        try:
            x.SR.assert_supports_database_replication(sr)
            return True
        except XenAPI.Failure:
            return False
    sr = next((ref for ref, r in x.SR.get_all_records().items()
               if r["shared"] and r["content_type"] != "iso" and supports_replication(ref)), None)
    if sr is None:
        raise RuntimeError("no shared SR here supports database replication (it needs iSCSI or HBA storage)")
    print("Replicating pool metadata to %s" % x.SR.get_name_label(sr))
    x.SR.enable_database_replication(sr)

    # Everything from here happens on the STANDBY pool, the way XenCenter's DR wizard works from the
    # pool you fail over to: it has the same SR attached, rescans it to see the metadata disk just
    # written, opens the database there, and recovers into itself - VM.recover's session_to has to be a
    # session of the server running the call (HANDLE_INVALID otherwise).
    d = dr_session.xenapi
    try:
        dr_sr = d.SR.get_by_uuid(x.SR.get_uuid(sr))
    except XenAPI.Failure:
        raise RuntimeError("the standby pool has not attached %s: attach the same storage there first"
                           % x.SR.get_name_label(sr))
    d.SR.scan(dr_sr)
    vdi = next((v for v in d.SR.get_VDIs(dr_sr) if d.VDI.get_type(v) == "metadata"), None)
    if vdi is None:
        raise RuntimeError("the standby pool sees no metadata disk on %s after rescanning it"
                           % d.SR.get_name_label(dr_sr))
    print("  metadata disk: %s" % d.VDI.get_uuid(vdi))

    # A session onto the replicated database rather than the live pool. The binding keeps the
    # session id in _session, so a second Session can be pointed at the one we were handed.
    metadata = XenAPI.Session(dr_url, ignore_ssl=True)
    metadata._session = d.VDI.open_database(vdi)

    # Only real guest VMs are recoverable - exclude templates, control domains and snapshots.
    recoverable = {ref: r for ref, r in metadata.xenapi.VM.get_all_records().items()
                   if not r["is_a_template"] and not r["is_control_domain"] and not r["is_a_snapshot"]}
    print("  the replicated database describes %d recoverable VM(s)" % len(recoverable))

    # Only a VM whose disks are all on storage the standby pool can see can be recovered there - the
    # check runs on the METADATA session, and session_to says where the VM should land: the standby
    # pool's own session. Take the first (by name) that passes, as the DR wizard lists them.
    dr_session_id = dr_session._session
    def can_be_recovered(ref):
        try:
            metadata.xenapi.VM.assert_can_be_recovered(ref, dr_session_id)
            return True
        except XenAPI.Failure:
            return False
    target = next((ref for ref in sorted(recoverable, key=lambda ref: recoverable[ref]["name_label"])
                   if can_be_recovered(ref)), None)
    if target is None:
        raise RuntimeError("no VM in the replicated database has all its disks on storage the standby "
                           "pool can see")
    target_uuid = recoverable[target]["uuid"]
    name = recoverable[target]["name_label"]
    print("  recovering %s" % name)
    metadata.xenapi.VM.recover(target, dr_session_id, False)

    # It is a real VM on the standby pool now, not merely a call that returned - look it up by the
    # uuid full_restore preserved, not by name.
    recovered = dr_session.xenapi.VM.get_by_uuid(target_uuid)
    print("  %s is %s on the standby pool" % (name, dr_session.xenapi.VM.get_power_state(recovered)))

    # Tidy up on the standby pool only, by uuid - never touch the source pool's VMs, and never
    # guess by name (a coincidentally-same-named VM must not be destroyed). Destroy the VM record but
    # NOT its disks: they are the protected pool's own disks on the shared SR, not copies.
    dr_session.xenapi.VM.destroy(recovered)
    x.SR.disable_database_replication(sr)
    print("OK: disaster-recovery")
    session.xenapi.session.logout()
    dr_session.xenapi.session.logout()
```

<details><summary>Sample output</summary>

```text
Replicating pool metadata to Shared NFS
  metadata disk: 00000001-0000-0000-b001-000000000000
  the replicated database describes 8 recoverable VM(s)
  recovering cache-01 (recovered)
  cache-01 (recovered) is Halted in the live pool
OK: disaster-recovery
```

</details>

## Java

Source: [`java/src/main/java/com/xenserver/samples/disasterrecovery/DisasterRecovery.java`](../../java/src/main/java/com/xenserver/samples/disasterrecovery/DisasterRecovery.java)

```java
package com.xenserver.samples.disasterrecovery;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.SR;
import com.xensource.xenapi.Session;
import com.xensource.xenapi.Types;
import com.xensource.xenapi.VDI;
import com.xensource.xenapi.VM;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;

import static com.xenserver.samples.PoolConnection.connect;

public final class DisasterRecovery {
    private DisasterRecovery() {
    }

    /**
     * Recover VMs after a disaster.
     *
     * <p>Replicate the pool's database to shared storage, read it back as a separate database to see what
     * it describes, and recover a VM out of it into a second, standby pool (dr_url).
     *
     * <p>Disaster recovery works by writing the pool's own database out to a storage repository as a disk
     * of type "metadata". That disk can be read back as a SEPARATE database - VDI.openDatabase hands you a
     * Session scoped to it - so the ordinary calls describe the pool as it was replicated rather than the
     * pool you are connected to. Recovering reads from that database and writes into a live pool, which is
     * why the recover call is made on the metadata session and takes a live session as its destination.
     *
     * <p>That destination has to be a DIFFERENT, standby pool: recovering a VM back into the exact pool it
     * was replicated from can't actually succeed with force=false. The VM's uuid already exists there, so
     * VM.recover always takes the replace-or-fail path, and nothing replicated a moment ago from a live
     * database can ever be "newer" than the live object it came from - it fails with
     * VM_TO_IMPORT_IS_NOT_NEWER_VERSION. The one-line "fix" of passing force=true instead would make it
     * succeed by REPLACING (destroying and recreating) the live original - exactly the opposite of what a
     * DR demo should show. A second pool is the only way force=false succeeds (a brand-new VM object, not
     * a replace), and it's what every real DR workflow actually does. Track the recovered VM by uuid,
     * never by name: a name can coincidentally collide with something already on the destination pool, and
     * tidy-up must never guess by name.
     *
     * <p>Run it:
     *
     * <pre>{@code
     * DisasterRecovery.run("https://xenserver", "root", password, "https://standby-pool");
     * }</pre>
     */
    public static void run(String url, String user, String password, String drUrl) throws Exception {
        if (drUrl == null || drUrl.isEmpty())
            throw new RuntimeException("disaster-recovery needs a second pool to recover into: pass "
                    + "dr_url=<url of a standby pool>");
        Connection conn = connect(url, user, password);
        Connection drConn = connect(drUrl, user, password);
        try {
            // Replication needs shared storage the standby pool can attach too, and only block storage
            // (iSCSI, HBA) supports it - an NFS SR fails SR_OPERATION_NOT_SUPPORTED. The server checks
            // rather than taking your word for it, so ask each candidate, as XenCenter's DR wizard does.
            SR sr = null;
            for (Map.Entry<SR, SR.Record> e : SR.getAllRecords(conn).entrySet()) {
                SR.Record r = e.getValue();
                if (!r.shared || "iso".equals(r.contentType)) continue;
                try {
                    e.getKey().assertSupportsDatabaseReplication(conn);
                    sr = e.getKey();
                    break;
                } catch (Types.XenAPIException notThisOne) {
                    // try the next one
                }
            }
            if (sr == null)
                throw new RuntimeException("no shared SR here supports database replication (it needs iSCSI or HBA storage)");
            System.out.println("Replicating pool metadata to " + sr.getNameLabel(conn));
            sr.enableDatabaseReplication(conn);

            // Everything from here happens on the STANDBY pool, the way XenCenter's DR wizard works from
            // the pool you fail over to: it has the same SR attached, rescans it to see the metadata disk
            // just written, opens the database there, and recovers into itself - VM.recover's session_to
            // has to be a session of the server running the call (HANDLE_INVALID otherwise).
            SR drSr;
            try {
                drSr = SR.getByUuid(drConn, sr.getUuid(conn));
            } catch (Types.XenAPIException e) {
                throw new RuntimeException("the standby pool has not attached " + sr.getNameLabel(conn)
                        + ": attach the same storage there first");
            }
            drSr.scan(drConn);
            VDI metadataVdi = null;
            for (VDI v : drSr.getVDIs(drConn))
                if (v.getType(drConn) == Types.VdiType.METADATA) { metadataVdi = v; break; }
            System.out.println("  metadata disk: " + metadataVdi.getUuid(drConn));

            // A session onto the replicated database rather than the live pool.
            Session metadata = metadataVdi.openDatabase(drConn);

            // The generated classes always send the Connection's own session, so reading the replicated
            // database means dispatching by hand with the metadata session in its place. Connection
            // .dispatch is the binding's own entry point, so this still goes over the trusting HTTP
            // client that connect() set up.
            Map<VM, VM.Record> all = drConn.dispatch("VM.get_all_records",
                new Object[]{metadata.toWireString()},
                new com.fasterxml.jackson.core.type.TypeReference<Map<VM, VM.Record>>() {});

            // Only real guest VMs are recoverable - exclude templates, control domains and snapshots.
            Map<VM, VM.Record> recoverable = new java.util.LinkedHashMap<>();
            for (Map.Entry<VM, VM.Record> e : all.entrySet()) {
                VM.Record r = e.getValue();
                if (!r.isATemplate && !r.isControlDomain && !r.isASnapshot) recoverable.put(e.getKey(), r);
            }
            System.out.printf("  the replicated database describes %d recoverable VM(s)%n", recoverable.size());

            // Only a VM whose disks are all on storage the standby pool can see can be recovered there -
            // the check runs on the METADATA session, and session_to says where the VM should land: the
            // STANDBY pool's session, not this one. Take the first (by name) that passes, as the DR
            // wizard lists them.
            String drSessionId = drConn.getSessionReference();
            List<Map.Entry<VM, VM.Record>> byName = new ArrayList<>(recoverable.entrySet());
            byName.sort(Map.Entry.comparingByValue((a, b) -> a.nameLabel.compareTo(b.nameLabel)));
            VM target = null;
            String name = null;
            String targetUuid = null;
            for (Map.Entry<VM, VM.Record> e : byName) {
                try {
                    drConn.<Object>dispatch("VM.assert_can_be_recovered",
                        new Object[]{metadata.toWireString(), e.getKey().toWireString(), drSessionId});
                } catch (Types.XenAPIException notThisOne) {
                    continue;
                }
                target = e.getKey(); name = e.getValue().nameLabel; targetUuid = e.getValue().uuid;
                break;
            }
            if (target == null)
                throw new RuntimeException("no VM in the replicated database has all its disks on storage the standby pool can see");
            System.out.println("  recovering " + name);
            drConn.<Object>dispatch("VM.recover",
                new Object[]{metadata.toWireString(), target.toWireString(), drSessionId, false});

            // It is a real VM on the standby pool now, not merely a call that returned - look it up by
            // the uuid full_restore preserved, not by name.
            VM recovered = VM.getByUuid(drConn, targetUuid);
            System.out.println("  " + name + " is " + recovered.getPowerState(drConn) + " on the standby pool");

            // Tidy up on the standby pool only, by uuid - never touch the source pool's VMs, and never
            // guess by name (a coincidentally-same-named VM must not be destroyed). Destroy the VM record
            // but NOT its disks: they are the protected pool's own disks on the shared SR, not copies.
            recovered.destroy(drConn);
            sr.disableDatabaseReplication(conn);
            System.out.println("OK: disaster-recovery");
        } finally {
            Session.logout(conn);
            Session.logout(drConn);
        }
    }
}
```

<details><summary>Sample output</summary>

```text
Replicating pool metadata to Shared NFS
  metadata disk: 00000001-0000-0000-b801-000000000000
  the replicated database describes 7 recoverable VM(s)
  recovering cache-01 (recovered)
  cache-01 (recovered) is Halted in the live pool
OK: disaster-recovery
```

</details>

## Go

Source: [`go/disaster_recovery.go`](../../go/disaster_recovery.go)

```go
package main

import (
	"encoding/json"
	"fmt"
	"sort"

	"go/xenapi"
)

// disasterRecovery - Recover VMs after a disaster.
//
// Replicate the pool's database to shared storage, read it back as a separate database to see what
// it describes, and recover a VM out of it into a second, standby pool (dr_url).
//
// Disaster recovery works by writing the pool's own database out to a storage repository as a disk
// of type "metadata". That disk can be read back as a SEPARATE database, so the ordinary calls
// describe the pool as it was replicated rather than the pool you are connected to. Recovering
// reads from that database and writes into a live pool, which is why the recover call is made on
// the metadata session and takes a live session as its destination.
//
// That destination has to be a DIFFERENT, standby pool: recovering a VM back into the exact pool
// it was replicated from can't actually succeed with force=false - the VM's uuid already exists
// there, so VM.recover always takes the replace-or-fail path, and nothing replicated a moment ago
// from a live database can ever be "newer" than the live object it came from
// (VM_TO_IMPORT_IS_NOT_NEWER_VERSION). The one-line "fix" of passing force=true instead would make
// it succeed by REPLACING (destroying and recreating) the live original - exactly the opposite of
// what a DR demo should show, and the thing that would actually destroy a live VM if ever pointed
// at the same pool it replicated from. A second pool is the only way force=false succeeds, and
// what every real DR workflow actually does. Track the recovered VM by uuid, never by name: a
// name can coincidentally collide with something already on the destination pool.
func disasterRecovery(url, user, password, drURL string) {
	if drURL == "" {
		panic("disaster-recovery needs a second pool to recover into: pass dr_url=<url of a standby pool>")
	}
	session := connect(url, user, password)
	defer session.Logout()
	drSession := connect(drURL, user, password)
	defer drSession.Logout()

	// Replication needs shared storage the standby pool can attach too, and only block storage (iSCSI,
	// HBA) supports it - an NFS SR fails SR_OPERATION_NOT_SUPPORTED. The server checks rather than taking
	// your word for it, so ask each candidate, as XenCenter's DR wizard does.
	srs, err := xenapi.SR.GetAllRecords(session)
	check(err)
	var sr xenapi.SRRef
	for ref, r := range srs {
		if r.Shared && r.ContentType != "iso" && xenapi.SR.AssertSupportsDatabaseReplication(session, ref) == nil {
			sr = ref
			break
		}
	}
	if sr == "" {
		panic("no shared SR here supports database replication (it needs iSCSI or HBA storage)")
	}
	srName, _ := xenapi.SR.GetNameLabel(session, sr)
	fmt.Printf("Replicating pool metadata to %s\n", srName)
	check(xenapi.SR.EnableDatabaseReplication(session, sr))

	// Everything from here happens on the STANDBY pool, the way XenCenter's DR wizard works from the pool
	// you fail over to: it has the same SR attached, rescans it to see the metadata disk just written,
	// opens the database there, and recovers into itself - VM.recover's session_to has to be a session of
	// the server running the call (HANDLE_INVALID otherwise).
	srUUID, err := xenapi.SR.GetUUID(session, sr)
	check(err)
	drSR, err := xenapi.SR.GetByUUID(drSession, srUUID)
	if err != nil {
		panic(fmt.Sprintf("the standby pool has not attached %s: attach the same storage there first", srName))
	}
	check(xenapi.SR.Scan(drSession, drSR))
	vdis, err := xenapi.SR.GetVDIs(drSession, drSR)
	check(err)
	var metadataVdi xenapi.VDIRef
	for _, v := range vdis {
		if t, _ := xenapi.VDI.GetType(drSession, v); t == xenapi.VdiTypeMetadata {
			metadataVdi = v
			break
		}
	}
	uuid, _ := xenapi.VDI.GetUUID(drSession, metadataVdi)
	fmt.Printf("  metadata disk: %s\n", uuid)

	metadataSession, err := xenapi.VDI.OpenDatabase(drSession, metadataVdi)
	check(err)

	// The Go binding keeps its session private and offers no way to build one from a session id it did
	// not create, so the metadata database has to be driven over plain JSON-RPC. Same reason the
	// destination pool's session id is obtained separately: recover() needs one to say where the VM
	// should land.
	drSessionID := rawLogin(drURL, user, password)
	var recoverable map[string]struct {
		UUID            string `json:"uuid"`
		NameLabel       string `json:"name_label"`
		IsATemplate     bool   `json:"is_a_template"`
		IsControlDomain bool   `json:"is_control_domain"`
		IsASnapshot     bool   `json:"is_a_snapshot"`
	}
	check(json.Unmarshal(rawRPC(drURL, "VM.get_all_records", string(metadataSession)), &recoverable))

	// Only real guest VMs are recoverable - exclude templates, control domains and snapshots.
	targets := make([]string, 0, len(recoverable))
	for ref, r := range recoverable {
		if !r.IsATemplate && !r.IsControlDomain && !r.IsASnapshot {
			targets = append(targets, ref)
		}
	}
	fmt.Printf("  the replicated database describes %d recoverable VM(s)\n", len(targets))

	sort.Slice(targets, func(i, j int) bool {
		return recoverable[targets[i]].NameLabel < recoverable[targets[j]].NameLabel
	})
	// Only a VM whose disks are all on storage the standby pool can see can be recovered there - the
	// check runs on the METADATA session, and session_to says where the VM should land: the STANDBY
	// pool's session, not this one. Take the first (by name) that passes, as the DR wizard lists them.
	target := ""
	for _, t := range targets {
		if _, failure := rawRPCCall(drURL, "VM.assert_can_be_recovered", string(metadataSession), t, drSessionID); failure == nil {
			target = t
			break
		}
	}
	if target == "" {
		panic("no VM in the replicated database has all its disks on storage the standby pool can see")
	}
	targetUUID := recoverable[target].UUID
	name := recoverable[target].NameLabel
	fmt.Printf("  recovering %s\n", name)

	// Never force=true: see the doc comment above.
	rawRPC(drURL, "VM.recover", string(metadataSession), target, drSessionID, false)

	// It is a real VM on the standby pool now, not merely a call that returned - look it up by the
	// uuid full_restore preserved, never by name.
	recovered, err := xenapi.VM.GetByUUID(drSession, targetUUID)
	check(err)
	ps, _ := xenapi.VM.GetPowerState(drSession, recovered)
	fmt.Printf("  %s is %s on the standby pool\n", name, ps)

	// Tidy up on the standby pool only, by uuid - never touch the source pool's VMs, and never guess
	// by name (a coincidentally-same-named VM must not be destroyed). Destroy the VM record but NOT its
	// disks: they are the protected pool's own disks on the shared SR, not copies.
	check(xenapi.VM.Destroy(drSession, recovered))

	check(xenapi.SR.DisableDatabaseReplication(session, sr))
	fmt.Println("OK: disaster-recovery")
}
```

<details><summary>Sample output</summary>

```text
Replicating pool metadata to Shared NFS
  metadata disk: 00000001-0000-0000-a801-000000000000
  the replicated database describes 6 recoverable VM(s)
  recovering cache-01 (recovered)
  cache-01 (recovered) is Halted in the live pool
OK: disaster-recovery
```

</details>

## PowerShell

Source: [`powershell/DisasterRecovery/Invoke-DisasterRecovery.ps1`](../../powershell/DisasterRecovery/Invoke-DisasterRecovery.ps1)

```powershell
function Invoke-DisasterRecovery {
    <#
    .SYNOPSIS
        Recover VMs after a disaster.
    .DESCRIPTION
        Replicate the pool's database to shared storage, read it back as a separate database to see what it
        describes, and recover a VM out of it into a second, standby pool (dr_url).
    .EXAMPLE
        Invoke-DisasterRecovery -Url https://xenserver -UserName root -Password $password
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password,
        [string]$DrUrl
    )
    # Disaster recovery works by writing the pool's own database out to a storage repository as a disk of
    # type "metadata". That disk can be read back as a SEPARATE database - VDI.open_database hands you a
    # session scoped to it - so the ordinary calls describe the pool as it was replicated rather than the
    # pool you are connected to. Recovering reads from that database and writes into a live pool, which
    # is why the recover call is made on the metadata session and takes a live session as its
    # destination.
    #
    # That destination has to be a DIFFERENT, standby pool: recovering a VM back into the exact pool it
    # was replicated from can't actually succeed with force=false. The VM's uuid already exists there, so
    # VM.recover always takes the replace-or-fail path, and nothing replicated a moment ago from a live
    # database can ever be "newer" than the live object it came from - it fails with
    # VM_TO_IMPORT_IS_NOT_NEWER_VERSION. The one-line "fix" of passing force=true instead would make it
    # succeed by REPLACING (destroying and recreating) the live original - exactly the opposite of what a
    # DR demo should show. A second pool is the only way force=false succeeds (a brand-new VM object, not
    # a replace), and it's what every real DR workflow actually does.
    if (-not $DrUrl) {
        throw "disaster-recovery needs a second pool to recover into: pass dr_url=<url of a standby pool>"
    }
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password
    $drSession = Connect-Example -Url $DrUrl -UserName $UserName -Password $Password

    # Replication needs shared storage the standby pool can attach too, and only block storage (iSCSI,
    # HBA) supports it - an NFS SR fails SR_OPERATION_NOT_SUPPORTED. The server checks rather than taking
    # your word for it, so ask each candidate, as XenCenter's DR wizard does.
    $sr = Get-XenSR -SessionOpaqueRef $session.opaque_ref | Where-Object {
        $_.shared -and $_.content_type -ne 'iso'
    } | Where-Object {
        try {
            $_ | Invoke-XenSR -SessionOpaqueRef $session.opaque_ref -XenAction AssertSupportsDatabaseReplication
            $true
        }
        catch { $false }
    } | Select-Object -First 1
    if (-not $sr) { throw "no shared SR here supports database replication (it needs iSCSI or HBA storage)" }
    Write-Host "Replicating pool metadata to $($sr.name_label)"
    $sr | Invoke-XenSR -SessionOpaqueRef $session.opaque_ref -XenAction EnableDatabaseReplication

    # Everything from here happens on the STANDBY pool, the way XenCenter's DR wizard works from the pool
    # you fail over to: it has the same SR attached, rescans it to see the metadata disk just written,
    # opens the database there, and recovers into itself - VM.recover's session_to has to be a session of
    # the server running the call (HANDLE_INVALID otherwise).
    $drSr = Get-XenSR -SessionOpaqueRef $drSession.opaque_ref | Where-Object { $_.uuid -eq $sr.uuid }
    if (-not $drSr) { throw "the standby pool has not attached $($sr.name_label): attach the same storage there first" }
    $drSr | Invoke-XenSR -SessionOpaqueRef $drSession.opaque_ref -XenAction Scan
    $vdi = Get-XenVDI -SessionOpaqueRef $drSession.opaque_ref |
        Where-Object { $_.type -eq 'metadata' -and $_.SR.opaque_ref -eq $drSr.opaque_ref } | Select-Object -First 1
    Write-Host "  metadata disk: $($vdi.uuid)"

    # Two module limits meet here, so the metadata database is driven over JSON-RPC: Invoke-XenVDI
    # -XenAction OpenDatabase does not hand back the session it opens (even with -PassThru), and
    # -SessionOpaqueRef only accepts sessions the module created itself. Same escape hatch the event API
    # needs, and still pure PowerShell.
    $metadataRef = Invoke-XenMethod -Session $drSession -Method 'VDI.open_database' -Params @($vdi.opaque_ref)
    $metadata = [pscustomobject]@{ opaque_ref = $metadataRef; Url = $drSession.Url }

    # Only real guest VMs are recoverable - exclude templates, control domains and snapshots.
    $allRecords = Invoke-XenMethod -Session $metadata -Method 'VM.get_all_records' -Params @()
    $recoverable = @($allRecords.PSObject.Properties | Where-Object {
            -not $_.Value.is_a_template -and -not $_.Value.is_control_domain -and -not $_.Value.is_a_snapshot
        } | Sort-Object { $_.Value.name_label })
    Write-Host "  the replicated database describes $($recoverable.Count) recoverable VM(s)"

    # Only a VM whose disks are all on storage the standby pool can see can be recovered there - the check
    # runs on the METADATA session, and session_to says where the VM should land: the STANDBY pool's
    # session, not this one. Take the first (by name) that passes, as the DR wizard lists them.
    $target = $recoverable | Where-Object {
        try {
            Invoke-XenMethod -Session $metadata -Method 'VM.assert_can_be_recovered' `
                -Params @($_.Name, $drSession.opaque_ref) | Out-Null
            $true
        }
        catch { $false }
    } | Select-Object -First 1
    if (-not $target) { throw "no VM in the replicated database has all its disks on storage the standby pool can see" }
    $targetUuid = $target.Value.uuid
    $name = $target.Value.name_label
    Write-Host "  recovering $name"

    # force stays false - never true (see above: that's the one-line "fix" that would actually destroy a
    # live VM if ever pointed at the source pool).
    Invoke-XenMethod -Session $metadata -Method 'VM.recover' `
        -Params @($target.Name, $drSession.opaque_ref, $false) | Out-Null

    # It is a real VM on the standby pool now, not merely a call that returned - look it up by the uuid
    # full_restore preserved, not by name, on the DESTINATION session. NO fallback to the source pool: a
    # second pool is the only correct target (see above), so this always looks up and tidies up on the
    # destination only.
    $recovered = Get-XenVM -SessionOpaqueRef $drSession.opaque_ref -Uuid $targetUuid
    Write-Host "  $name is $($recovered.power_state) on the standby pool"

    # Tidy up on the standby pool only, by uuid - never guess by name, and never touch the source pool.
    # Destroy the VM record but NOT its disks: they are the protected pool's own disks on the shared SR,
    # not copies.
    Remove-XenVM -SessionOpaqueRef $drSession.opaque_ref -Ref $recovered.opaque_ref

    $sr | Invoke-XenSR -SessionOpaqueRef $session.opaque_ref -XenAction DisableDatabaseReplication
    Write-Host "OK: disaster-recovery"
    $session | Disconnect-XenServer
    $drSession | Disconnect-XenServer
}
```

<details><summary>Sample output</summary>

```text
Replicating pool metadata to Shared NFS
  metadata disk: 00000001-0000-0000-be01-000000000000
  the replicated database describes 4 recoverable VM(s)
  recovering cache-01 (recovered)
  cache-01 (recovered) is Halted in the live pool
OK: disaster-recovery
```

</details>

## xe CLI

Source: [`cli/disaster-recovery/disaster-recovery.sh`](../../cli/disaster-recovery/disaster-recovery.sh)

```bash
# Recover VMs after a disaster.
#
# Replicate the pool's database to shared storage, read it back as a separate database to see what it
# describes, and recover a VM out of it into a second, standby pool (dr_url).
#
# Run it:
#   ./workflows.sh disaster-recovery https://xenserver root "$password"
#
# Optional key=value arguments (default):
#   dr_url ("")

# Disaster recovery works by writing the pool's own database out to a storage repository as a disk of type
# "metadata", then reading that back as a SEPARATE database to recover a VM out of it onto a second,
# standby pool. Recovering a VM back into the exact pool it was replicated from can't actually succeed with
# force=false (its uuid already exists there, so VM.recover always takes the replace-or-fail path and
# nothing replicated a moment ago from a live database can ever be "newer" than the live object it came
# from) - force=true would "fix" that by REPLACING (destroying and recreating) the live original, which is
# the one thing a DR demo must never do. A second pool is the only correct target, which is why this needs
# dr_url and has no default: pass dr_url=<url of a standby pool>. xe has no "session_to" argument to carry
# this (unlike the SDK languages' session-based VM.recover): instead, run the assert/recover calls on a
# connection opened to the standby pool itself, pointed at the metadata disk by uuid - the storage it lives
# on has to be reachable from the standby pool too, which is the whole premise of DR replication.
disaster_recovery() {
    local dr_url dr_host dr_hp dr_probe
    local -a dr_opts
    dr_url=$(param dr_url "")
    if [ -z "$dr_url" ]; then
        echo "disaster-recovery needs a second pool to recover into: pass dr_url=<url of a standby pool>" >&2
        exit 1
    fi
    dr_hp=${dr_url#*://}; dr_hp=${dr_hp%%/*}
    dr_host=${dr_hp%%:*}
    dr_opts=()
    if [ "$dr_hp" != "$dr_host" ] && [ "${dr_hp##*:}" != 443 ]; then dr_opts=(-p $((${dr_hp##*:} + 1))); fi
    case "${XE_EXE:-xe}" in *.exe | *.EXE) dr_opts+=(-no-warn-new-certificates -no-warn-certificates) ;; esac
    xe_dr() { command "${XE_EXE:-xe}" -s "$dr_host" "${dr_opts[@]}" -u "$user" -pw "$pass" "$@"; }
    # Follow HOST_IS_SLAVE on the standby pool too, the same one-time probe the main connection does.
    dr_probe=$(xe_dr pool-list --minimal 2>&1) || true
    if [[ $dr_probe =~ (Master|Coordinator)\ IP\ address:\ ([0-9A-Fa-f.:]+) ]]; then dr_host=${BASH_REMATCH[2]}; fi

    # Replication needs shared storage the standby pool can attach too, and only block storage (iSCSI,
    # HBA) supports it - an NFS SR fails SR_OPERATION_NOT_SUPPORTED. xe has no assert for it, so try each
    # shared SR in turn until one takes it.
    sr=""
    for candidate in $(each_csv "$(xe sr-list shared=true content-type=user --minimal)"); do
        if xe sr-enable-database-replication uuid=$candidate 2>/dev/null; then sr=$candidate; break; fi
    done
    if [ -z "$sr" ]; then
        echo "no shared SR here supports database replication (it needs iSCSI or HBA storage)" >&2
        exit 1
    fi
    echo "Replicating pool metadata to $(xe sr-param-get uuid=$sr param-name=name-label)"

    # Everything from here happens on the STANDBY pool, the way XenCenter's DR wizard works from the pool
    # you fail over to: it has the same SR attached, rescans it to see the metadata disk just written,
    # reads the database there, and recovers into itself.
    if [ -z "$(xe_dr sr-list uuid=$sr --minimal)" ]; then
        echo "the standby pool has not attached this SR: attach the same storage there first" >&2
        exit 1
    fi
    xe_dr sr-scan uuid=$sr
    # The type reads "Metadata" in xe's output, so compare it case-insensitively rather than filtering.
    vdi=""
    for v in $(each_csv "$(xe_dr vdi-list sr-uuid=$sr --minimal)"); do
        t=$(xe_dr vdi-param-get uuid=$v param-name=type)
        if [ "${t,,}" = metadata ]; then vdi=$v; break; fi
    done
    if [ -z "$vdi" ]; then
        echo "the standby pool sees no metadata disk on this SR after rescanning it" >&2
        exit 1
    fi
    echo "  metadata disk: $vdi"

    # `database:vdi-uuid=` runs the command against the replicated database instead of the live pool, so
    # this lists the VMs as they were written out rather than the ones running now - only real guest VMs
    # are recoverable, so exclude templates, control domains and snapshots.
    recoverable=$(xe_dr vm-list database:vdi-uuid=$vdi is-a-template=false is-control-domain=false \
        is-a-snapshot=false --minimal)
    echo "  the replicated database describes $(count_csv "$recoverable") recoverable VM(s)"

    # Only a VM whose disks are all on storage the standby pool can see can be recovered there. Take the
    # first that passes the check, as the DR wizard lists them.
    md=""
    for candidate in $(each_csv "$recoverable"); do
        if xe_dr vm-assert-can-be-recovered uuid=$candidate database:vdi-uuid=$vdi 2>/dev/null; then
            md=$candidate; break
        fi
    done
    if [ -z "$md" ]; then
        echo "no VM in the replicated database has all its disks on storage the standby pool can see" >&2
        exit 1
    fi
    name=$(xe_dr vm-list uuid=$md database:vdi-uuid=$vdi params=name-label --minimal)
    echo "  recovering $name"
    xe_dr vm-recover uuid=$md database:vdi-uuid=$vdi force=false

    # It is a real VM on the standby pool now, not merely a command that returned - look it up there, by
    # the uuid full_restore preserved, never by name (a name can coincidentally collide with something
    # already on the destination pool).
    echo "  $name is $(xe_dr vm-param-get uuid=$md param-name=power-state) on the standby pool"

    # Tidy up on the standby pool only, by uuid - never touch the source pool's VMs. vm-destroy, not
    # vm-uninstall: the disks are the protected pool's own disks on the shared SR, not copies.
    xe_dr vm-destroy uuid=$md
    xe sr-disable-database-replication uuid=$sr
    echo "OK: disaster-recovery"
}
```

<details><summary>Sample output</summary>

```text
Replicating pool metadata to Shared NFS
  metadata disk: 00000001-0000-0000-c201-000000000000
  the replicated database describes 8 recoverable VM(s)
  recovering web-01 (recovered)
  web-01 (recovered) is Halted in the live pool
OK: disaster-recovery
```

</details>
