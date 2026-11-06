package com.xenserver.samples.storage;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.Host;
import com.xensource.xenapi.SR;
import com.xensource.xenapi.Secret;
import com.xensource.xenapi.Session;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.StringJoiner;

import static com.xenserver.samples.Helpers.firstTagText;
import static com.xenserver.samples.Helpers.parseXml;
import static com.xenserver.samples.Helpers.probeForFailure;
import static com.xenserver.samples.PoolConnection.connect;

public final class CreateIscsiSr {
    private CreateIscsiSr() {
    }

    /**
     * Create an iSCSI SR.
     *
     * <p>Connect a storage repository to a LUN on an iSCSI target, discovering the target's IQNs and then
     * the LUNs behind one. Creating the SR formats the LUN, and a shared array offers many targets, so
     * name yours with target_iqn; if the target behind it offers more than one LUN, name yours with
     * scsi_id too.
     *
     * <p>Connect an SR to a LUN on the iSCSI target, discovering the IQN and the LUN first: a
     * device-config that's missing a piece makes the backend fail on purpose, and the failure carries an
     * XML fragment listing what it needs next. SR.create formats the chosen LUN - this is destructive,
     * so pick carefully on a real target: pass targetIqn to name yours (see chooseTargetIqn), and scsiId
     * too if more than one LUN is offered behind it (see chooseLun). Before creating, this probes the
     * chosen LUN itself to make sure it is not already in use by another SR - formatting over one would
     * destroy it.
     *
     * <p>The CHAP password (if any) travels as a Secret, not plaintext device-config, as CreateSmbSr
     * already does for its share password.
     *
     * <p>Run it:
     *
     * <pre>{@code
     * CreateIscsiSr.run("https://xenserver", "root", password, "192.0.2.30", null, null, null, null, null,
     *     "sdk-example-iscsi");
     * }</pre>
     */
    public static void run(String url, String user, String password, String target,
            String port, String chapUser, String chapPassword, String targetIqn, String scsiId,
            String srName) throws Exception {
        final long GiB = 1024L * 1024 * 1024;
        Connection conn = connect(url, user, password);
        Secret secret = null;
        try {
            Host host = Host.getAllRecords(conn).keySet().iterator().next();
            Map<String, String> dc = new java.util.HashMap<>();
            dc.put("target", target);
            if (port != null && !port.isEmpty()) dc.put("port", port);
            if (chapUser != null && !chapUser.isEmpty()) {
                dc.put("chapuser", chapUser);
                Secret.Record secretRec = new Secret.Record();
                secretRec.value = chapPassword;
                secretRec.otherConfig = new java.util.HashMap<>();
                secret = Secret.create(conn, secretRec);
                dc.put("chappassword_secret", secret.getUuid(conn));
            }

            // First failing probe: target only -> the backend lists the IQNs it offers.
            org.w3c.dom.Element iqnRoot = parseXml(probeForFailure(conn, host, dc, "lvmoiscsi")).getDocumentElement();
            dc.put("targetIQN", chooseTargetIqn(iqnRoot, target, targetIqn));
            System.out.println("Discovered IQN: " + dc.get("targetIQN"));

            // Second failing probe: +targetIQN -> the backend lists the LUNs behind it. Real create also
            // carries LUNid whenever it is known.
            org.w3c.dom.Element lunRoot = parseXml(probeForFailure(conn, host, dc, "lvmoiscsi")).getDocumentElement();
            org.w3c.dom.NodeList lunNodes = lunRoot.getElementsByTagName("LUN");
            List<org.w3c.dom.Element> luns = new ArrayList<>();
            for (int i = 0; i < lunNodes.getLength(); i++) luns.add((org.w3c.dom.Element) lunNodes.item(i));
            org.w3c.dom.Element lun = chooseLun(luns, scsiId);
            dc.put("SCSIid", firstTagText(lun, "SCSIid"));
            String lunId = firstTagText(lun, "LUNid");
            dc.put("LUNid", lunId != null ? lunId : String.valueOf(luns.indexOf(lun)));
            System.out.println("Discovered LUN " + dc.get("LUNid") + " (SCSIid " + dc.get("SCSIid") + ")");

            // The device-config is now complete enough to create from - which means it is also complete
            // enough to probe the LUN itself: an <SR> in the answer means one is already there, and
            // SR.create would format it. Reattach that SR rather than destroying it.
            org.w3c.dom.Element srListRoot =
                parseXml(SR.probe(conn, host, dc, "lvmoiscsi", new java.util.HashMap<>())).getDocumentElement();
            org.w3c.dom.NodeList existing = srListRoot.getElementsByTagName("SR");
            if (existing.getLength() > 0) {
                String uuid = firstTagText((org.w3c.dom.Element) existing.item(0), "UUID");
                throw new RuntimeException("LUN " + dc.get("SCSIid") + " already holds SR "
                    + (uuid == null ? "?" : uuid.trim()) + "; creating an SR here would format it - "
                    + "reattach the existing SR instead of creating a new one");
            }

            SR sr = SR.create(conn, host, dc, 0L, srName, "iSCSI SR created by the SDK example",
                "lvmoiscsi", "user", true, new java.util.HashMap<>());
            System.out.println("Created SR: " + sr.getUuid(conn) + " (" + sr.getPhysicalSize(conn) / GiB + " GiB)");
            // Tidy up: this example created the SR, so destroy it - a forgotten SR would stay on the LUN.
            // SR.destroy needs it detached from every host first.
            for (com.xensource.xenapi.PBD pbd : sr.getPBDs(conn))
                if (pbd.getCurrentlyAttached(conn)) pbd.unplug(conn);
            sr.destroy(conn);
        } finally {
            if (secret != null) secret.destroy(conn);
            Session.logout(conn);
        }
        System.out.println("OK: create-iscsi-sr");
    }

    /**
     * Pick the IQN from an iSCSI discovery probe: the caller's, if named (it must be one the target
     * offers), else the first. An array usually offers many targets - one per LUN, often belonging to
     * different users - so on shared storage always name yours: SR.create formats the LUN behind it.
     */
    private static String chooseTargetIqn(org.w3c.dom.Element iqnRoot, String target, String targetIqn) {
        org.w3c.dom.NodeList nodes = iqnRoot.getElementsByTagName("TargetIQN");
        List<String> offered = new ArrayList<>();
        for (int i = 0; i < nodes.getLength(); i++) offered.add(nodes.item(i).getTextContent());
        if (targetIqn == null || targetIqn.isEmpty()) return offered.get(0);
        if (!offered.contains(targetIqn))
            throw new RuntimeException("target " + target + " does not offer IQN " + targetIqn);
        return targetIqn;
    }

    /**
     * Pick the LUN behind the chosen IQN: the caller's SCSIid, if named (it must be one on offer), else
     * the one LUN, if that target offers only one. Choose a LUN automatically only when exactly one is
     * on offer, and otherwise make the caller choose - picking blindly on a shared target risks
     * formatting someone else's disk.
     */
    private static org.w3c.dom.Element chooseLun(List<org.w3c.dom.Element> luns, String scsiId) {
        if (scsiId != null && !scsiId.isEmpty()) {
            for (org.w3c.dom.Element lun : luns) {
                if (scsiId.equals(firstTagText(lun, "SCSIid"))) return lun;
            }
            StringJoiner offered = new StringJoiner(", ");
            for (org.w3c.dom.Element lun : luns) offered.add(firstTagText(lun, "SCSIid"));
            throw new RuntimeException("target does not offer a LUN with SCSIid " + scsiId + "; offered: " + offered);
        }
        if (luns.size() == 1) return luns.get(0);
        StringJoiner offered = new StringJoiner(", ");
        for (org.w3c.dom.Element lun : luns) {
            offered.add(firstTagText(lun, "SCSIid") + " (" + firstTagText(lun, "size") + " bytes)");
        }
        throw new RuntimeException("target offers " + luns.size() + " LUNs; name one with scsiId: " + offered);
    }
}
