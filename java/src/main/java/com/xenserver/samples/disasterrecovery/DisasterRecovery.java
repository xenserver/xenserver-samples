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
