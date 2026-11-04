package com.xenserver.samples.storage;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.Host;
import com.xensource.xenapi.SR;
import com.xensource.xenapi.Session;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;

import static com.xenserver.samples.Helpers.detachAndForgetSr;
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
     * the LUNs behind one, as the New SR wizard does. Creating the SR formats the LUN, and a shared array
     * offers many targets, so name yours with target_iqn.
     *
     * <p>Connect an SR to a LUN on the iSCSI target, discovering the IQN and the LUN the way the New SR
     * wizard does: a device-config that's missing a piece makes the backend fail on purpose, and the
     * failure carries an XML fragment listing what it needs next. SR.create formats the chosen LUN -
     * this is destructive, so pick carefully on a real target: pass targetIqn to name yours (see
     * chooseTargetIqn).
     *
     * <p>Run it:
     *
     * <pre>{@code
     * CreateIscsiSr.run("https://xenserver", "root", password, "192.0.2.30", null, null, null, null, "sdk-example-iscsi");
     * }</pre>
     */
    public static void run(String url, String user, String password, String target,
            String port, String chapUser, String chapPassword, String targetIqn, String srName) throws Exception {
        final long GiB = 1024L * 1024 * 1024;
        Connection conn = connect(url, user, password);
        try {
            Host host = Host.getAllRecords(conn).keySet().iterator().next();
            Map<String, String> dc = new java.util.HashMap<>();
            dc.put("target", target);
            if (port != null && !port.isEmpty()) dc.put("port", port);
            if (chapUser != null && !chapUser.isEmpty()) {
                dc.put("chapuser", chapUser);
                dc.put("chappassword", chapPassword);
            }

            // First failing probe: target only -> the backend lists the IQNs it offers.
            org.w3c.dom.Element iqnRoot = parseXml(probeForFailure(conn, host, dc, "lvmoiscsi")).getDocumentElement();
            dc.put("targetIQN", chooseTargetIqn(iqnRoot, target, targetIqn));
            System.out.println("Discovered IQN: " + dc.get("targetIQN"));

            // Second failing probe: +targetIQN -> the backend lists the LUNs behind it. Real create also
            // carries LUNid whenever it is known.
            org.w3c.dom.Element lunRoot = parseXml(probeForFailure(conn, host, dc, "lvmoiscsi")).getDocumentElement();
            org.w3c.dom.Element lun = (org.w3c.dom.Element) lunRoot.getElementsByTagName("LUN").item(0);
            dc.put("SCSIid", firstTagText(lun, "SCSIid"));
            String lunId = firstTagText(lun, "LUNid");
            dc.put("LUNid", lunId != null ? lunId : "0");
            System.out.println("Discovered LUN " + dc.get("LUNid") + " (SCSIid " + dc.get("SCSIid") + ")");

            SR sr = SR.create(conn, host, dc, 0L, srName, "iSCSI SR created by the SDK example",
                "lvmoiscsi", "user", true, new java.util.HashMap<>());
            System.out.println("Created SR: " + sr.getUuid(conn) + " (" + sr.getPhysicalSize(conn) / GiB + " GiB)");
            detachAndForgetSr(conn, sr);
            System.out.println("OK: create-iscsi-sr");
        } finally {
            Session.logout(conn);
        }
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
}
