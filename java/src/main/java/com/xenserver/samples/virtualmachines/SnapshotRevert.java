package com.xenserver.samples.virtualmachines;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.Session;
import com.xensource.xenapi.Types;
import com.xensource.xenapi.VM;

import org.apache.hc.client5.http.classic.methods.HttpGet;
import org.apache.hc.client5.http.impl.classic.CloseableHttpClient;
import org.apache.hc.core5.http.io.entity.EntityUtils;

import static com.xenserver.samples.Helpers.destroyVmAndDisks;
import static com.xenserver.samples.Helpers.vmByName;
import static com.xenserver.samples.PoolConnection.connect;
import static com.xenserver.samples.PoolConnection.trustingHttpClient;

public final class SnapshotRevert {
    private SnapshotRevert() {
    }

    /**
     * Snapshot &amp; revert.
     *
     * <p>Take a snapshot of a VM and then revert the VM back to that point-in-time, as you would before a
     * risky change.
     *
     * <p>Run it:
     *
     * <pre>{@code
     * SnapshotRevert.run("https://xenserver", "root", password, "web-01", "sdk-example-snapshot");
     * }</pre>
     */
    public static void run(String url, String user, String password,
            String vmName, String snapshotName) throws Exception {
        Connection conn = connect(url, user, password);
        VM vm = vmByName(conn, vmName);
        System.out.println("Snapshotting VM: " + vm.getNameLabel(conn));
        boolean wasRunning = vm.getPowerState(conn) == Types.VmPowerState.RUNNING;

        VM snap = vm.snapshot(conn, snapshotName);
        System.out.println("Created snapshot: " + snap.getUuid(conn));

        // A client shows a thumbnail of what was on screen when the snapshot was taken, captured from the
        // VM's console at that moment. It is an HTTP transfer alongside the API, not an API call, so the
        // session id travels in the query string. ref names the VM's VNC (rfb) console (the VM itself
        // works too). Only a running VM has a console to capture, and a host that can't reach it answers
        // 404 or 500 instead of an image: the picture is incidental, so carry on.
        if (vm.getPowerState(conn) == Types.VmPowerState.RUNNING) {
            com.xensource.xenapi.Console console = null;
            for (com.xensource.xenapi.Console c : vm.getConsoles(conn)) {
                if (c.getProtocol(conn) == Types.ConsoleProtocol.RFB) { console = c; break; }
            }
            HttpGet thumbGet = new HttpGet(url + "/vncsnapshot?session_id=" + conn.getSessionReference()
                    + "&ref=" + console.toWireString());
            try (CloseableHttpClient http = trustingHttpClient()) {
                String thumb = http.execute(thumbGet, resp -> resp.getCode() == 200
                        ? EntityUtils.toByteArray(resp.getEntity()).length + " bytes of PNG"
                        : "none (the host answered HTTP " + resp.getCode() + ")");
                System.out.println("Thumbnail:      " + thumb);
            }
        } else {
            System.out.println("Thumbnail:      none (the VM is not running, so it has no console)");
        }

        snap.revert(conn);
        System.out.println("Reverted VM to the snapshot.");

        // Reverting to a plain snapshot always leaves the VM Halted (xapi hard-shuts-down a running VM
        // before reverting it), even if it was Running a moment ago - restart it afterwards if that's how
        // we found it, so the workflow actually restores what it changed.
        if (wasRunning) {
            vm.start(conn, false, true);
            System.out.println("Restarted the VM (it was running before the revert).");
        }

        // A snapshot is itself a (special) VM record, with its own snapshot disks; destroy both to clean up
        // (the source VM's disks are untouched - they are not the snapshot's).
        destroyVmAndDisks(conn, snap);
        System.out.println("OK: snapshot-revert");
        Session.logout(conn);
    }
}
