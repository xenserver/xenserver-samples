package com.xenserver.samples.disasterrecovery;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.Pool;
import com.xensource.xenapi.SR;
import com.xensource.xenapi.Session;
import com.xensource.xenapi.Types;
import com.xensource.xenapi.VDI;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.StringJoiner;

import static com.xenserver.samples.PoolConnection.connect;

public final class ConfigureDisasterRecovery {
    private ConfigureDisasterRecovery() {
    }

    /**
     * Configure disaster recovery.
     *
     * <p>Turn on pool metadata replication: the pool writes its database - the configuration of its VMs
     * and vApps - to a disk on an iSCSI or Fibre Channel SR, as XenCenter's Configure DR dialog does. Have
     * your storage array replicate that SR, and the VMs' SRs, to the disaster recovery site; a pool there
     * can then recover the VMs from the replica (see {@link DisasterRecoveryFailover}).
     *
     * <p>Only SRs on a LUN - iSCSI or Fibre Channel/SAS (HBA) - can hold the pool's database, and every host
     * must have the SR attached. The server says which qualify: SR.assert_supports_database_replication
     * fails for any that can't (an NFS SR fails SR_OPERATION_NOT_SUPPORTED), so ask each one rather than
     * guessing from its type, as the Configure DR dialog does. A pool can replicate to up to 8 SRs.
     *
     * <p>Replication is only useful while it is on. So that the example leaves the pool as it found it, it
     * turns replication off again if it was off to start with; in practice, leave it on.
     *
     * <p>Run it:
     *
     * <pre>{@code
     * ConfigureDisasterRecovery.run("https://xenserver", "root", password, null);
     * }</pre>
     */
    public static void run(String url, String user, String password, String srName) throws Exception {
        Connection conn = connect(url, user, password);
        try {
            List<SR> candidates = new ArrayList<>();
            StringJoiner names = new StringJoiner(", ");
            for (Map.Entry<SR, SR.Record> e : SR.getAllRecords(conn).entrySet()) {
                SR.Record r = e.getValue();
                if (!r.shared || "iso".equals(r.contentType)) continue;
                try {
                    e.getKey().assertSupportsDatabaseReplication(conn);
                } catch (Types.XenAPIException cannot) {
                    continue;
                }
                candidates.add(e.getKey());
                names.add(r.nameLabel);
            }
            System.out.println("SRs that can hold the pool metadata: "
                    + (candidates.isEmpty() ? "none" : names.toString()));
            if (srName != null && !srName.isEmpty()) {
                List<SR> named = new ArrayList<>();
                for (SR sr : candidates)
                    if (srName.equals(sr.getNameLabel(conn))) named.add(sr);
                candidates = named;
            }
            if (candidates.isEmpty())
                throw new RuntimeException("no SR here can hold the pool metadata"
                        + (srName != null && !srName.isEmpty() ? " named '" + srName + "'" : "")
                        + ": it needs an iSCSI or Fibre Channel SR attached to every host");
            SR sr = candidates.get(0);
            String name = sr.getNameLabel(conn);

            // The pool's own metadata disk on this SR is what says replication is on (as the Configure DR
            // dialog decides): a disk of type metadata whose metadata_of_pool is this pool.
            Pool pool = Pool.getAll(conn).iterator().next();
            boolean wasOn = metadataDisk(conn, sr, pool) != null;
            if (wasOn) {
                System.out.println("The pool metadata is already replicated to " + name);
            } else {
                System.out.println("Replicating the pool metadata to " + name);
                sr.enableDatabaseReplication(conn);
            }

            VDI vdi = metadataDisk(conn, sr, pool);
            System.out.printf("  metadata disk: %s (%s), %d MiB, up to date: %s%n", vdi.getNameLabel(conn),
                    vdi.getUuid(conn), vdi.getVirtualSize(conn) / (1024 * 1024), vdi.getMetadataLatest(conn));

            if (!wasOn) {
                // Turning replication off destroys the metadata disk.
                sr.disableDatabaseReplication(conn);
                System.out.println("Turned replication off again, as it was before");
            }
            System.out.println("OK: configure-disaster-recovery");
        } finally {
            Session.logout(conn);
        }
    }

    private static VDI metadataDisk(Connection conn, SR sr, Pool pool) throws Exception {
        for (VDI v : sr.getVDIs(conn))
            if (v.getType(conn) == Types.VdiType.METADATA
                    && v.getMetadataOfPool(conn).toWireString().equals(pool.toWireString()))
                return v;
        return null;
    }
}
