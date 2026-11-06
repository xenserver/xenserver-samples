package com.xenserver.samples.storage;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.Host;
import com.xensource.xenapi.SR;
import com.xensource.xenapi.Session;

import java.util.Map;

import static com.xenserver.samples.Helpers.firstTagText;
import static com.xenserver.samples.Helpers.parseXml;
import static com.xenserver.samples.Helpers.probeForFailure;
import static com.xenserver.samples.PoolConnection.connect;

public final class CreateHbaSr {
    private CreateHbaSr() {
    }

    /**
     * Create an HBA SR.
     *
     * <p>Connect a shared storage repository to a fibre-channel (HBA) LUN: discover the LUNs the host can
     * see with a deliberately failing probe, then create the SR by SCSI ID. Creating the SR formats the
     * LUN.
     *
     * <p>Connect a shared SR to a fibre-channel (HBA) LUN, discovering it first: probing with no SCSIid
     * fails on purpose and lists every LUN the backend can see. SR.create formats the chosen LUN - this
     * is destructive, so pick carefully on a real target.
     *
     * <p>Run it:
     *
     * <pre>{@code
     * CreateHbaSr.run("https://xenserver", "root", password, "<SCSIid of your LUN>", "sdk-example-hba");
     * }</pre>
     */
    public static void run(String url, String user, String password, String scsiId, String srName)
            throws Exception {
        final long GiB = 1024L * 1024 * 1024;
        Connection conn = connect(url, user, password);
        try {
            Host host = Host.getAllRecords(conn).keySet().iterator().next();

            // The root element varies by backend; find BlockDevice entries by tag wherever they are.
            org.w3c.dom.Element devlistRoot =
                parseXml(probeForFailure(conn, host, new java.util.HashMap<>(), "lvmohba")).getDocumentElement();
            // SR.create formats the LUN: on shared FC storage name yours (scsiId); with none, the first is taken.
            org.w3c.dom.NodeList devices = devlistRoot.getElementsByTagName("BlockDevice");
            org.w3c.dom.Element device = null;
            for (int i = 0; i < devices.getLength() && device == null; i++) {
                org.w3c.dom.Element d = (org.w3c.dom.Element) devices.item(i);
                if (scsiId.isEmpty() || firstTagText(d, "SCSIid").equals(scsiId)) device = d;
            }
            if (device == null) throw new RuntimeException("no LUN with SCSIid " + scsiId + " is visible to this host");
            scsiId = firstTagText(device, "SCSIid");
            String path = firstTagText(device, "path");
            System.out.println("Discovered LUN: SCSIid " + scsiId + " on " + path);

            // SCSIid is all lvmohba needs. (The probe's <path> is for display: on a real host it reads like
            // "/dev/sde [sdc] [sdg] [sdi]", one entry per path.)
            Map<String, String> dc = new java.util.HashMap<>();
            dc.put("SCSIid", scsiId);

            // SCSIid alone is also enough to probe the LUN itself: an <SR> in the answer means one is
            // already there, and SR.create would format it. Reattach that SR rather than
            // destroying it.
            org.w3c.dom.Element srListRoot =
                parseXml(SR.probe(conn, host, dc, "lvmohba", new java.util.HashMap<>())).getDocumentElement();
            org.w3c.dom.NodeList existing = srListRoot.getElementsByTagName("SR");
            if (existing.getLength() > 0) {
                String uuid = firstTagText((org.w3c.dom.Element) existing.item(0), "UUID");
                throw new RuntimeException("LUN " + scsiId + " already holds SR "
                    + (uuid == null ? "?" : uuid.trim()) + "; creating an SR here would format it - "
                    + "reattach the existing SR instead of creating a new one");
            }

            SR sr = SR.create(conn, host, dc, 0L, srName, "HBA SR created by the SDK example",
                "lvmohba", "user", true, new java.util.HashMap<>());
            System.out.println("Created SR: " + sr.getUuid(conn) + " (" + sr.getPhysicalSize(conn) / GiB + " GiB)");
            // Tidy up: this example created the SR, so destroy it - a forgotten SR would stay on the LUN.
            // SR.destroy needs it detached from every host first.
            for (com.xensource.xenapi.PBD pbd : sr.getPBDs(conn))
                if (pbd.getCurrentlyAttached(conn)) pbd.unplug(conn);
            sr.destroy(conn);
            System.out.println("OK: create-hba-sr");
        } finally {
            Session.logout(conn);
        }
    }
}
