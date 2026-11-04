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
     * pool's storage, read the pool metadata replicated to it, and recover the VMs and vApps it describes -
     * as XenCenter's Disaster Recovery wizard does. By default this is a test failover, which removes what
     * it recovered and detaches the storage again.
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

                    // A pool often has no name of its own; XenCenter shows its coordinator's name instead.
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
