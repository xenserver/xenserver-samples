package com.xenserver.samples;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.Host;
import com.xensource.xenapi.PBD;
import com.xensource.xenapi.Pool;
import com.xensource.xenapi.Repository;
import com.xensource.xenapi.SR;
import com.xensource.xenapi.Session;
import com.xensource.xenapi.Task;
import com.xensource.xenapi.Types;
import com.xensource.xenapi.VBD;
import com.xensource.xenapi.VDI;
import com.xensource.xenapi.VM;
import com.xensource.xenapi.VMGuestMetrics;

import java.net.URL;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.LinkedHashSet;
import java.util.Map;
import java.util.Set;

import static com.xenserver.samples.PoolConnection.connect;

/**
 * Small helpers several workflows share: finding objects by name, waiting for the guest agent, tidying
 * up what an example created.
 */
public final class Helpers {
    private Helpers() {
    }

    /**
     * Look up a template VM by its exact name (rather than picking an arbitrary one).
     */
    public static VM templateByName(Connection conn, String name) throws Exception {
        for (Map.Entry<VM, VM.Record> e : VM.getAllRecords(conn).entrySet())
            if (e.getValue().isATemplate && name.equals(e.getValue().nameLabel)) return e.getKey();
        throw new RuntimeException("no template named '" + name + "' was found");
    }

    /**
     * Look up a guest VM (not a template, control domain or snapshot) by its exact name.
     */
    public static VM vmByName(Connection conn, String name) throws Exception {
        for (Map.Entry<VM, VM.Record> e : VM.getAllRecords(conn).entrySet()) {
            VM.Record r = e.getValue();
            if (!r.isATemplate && !r.isControlDomain && !r.isASnapshot && name.equals(r.nameLabel))
                return e.getKey();
        }
        throw new RuntimeException("no VM named '" + name + "' was found");
    }

    /**
     * Look up an SR by its exact name (optionally requiring it to be shared).
     */
    public static SR srByName(Connection conn, String name, boolean shared) throws Exception {
        for (Map.Entry<SR, SR.Record> e : SR.getAllRecords(conn).entrySet())
            if (name.equals(e.getValue().nameLabel) && (!shared || e.getValue().shared)) return e.getKey();
        throw new RuntimeException("no " + (shared ? "shared " : "") + "SR named '" + name + "' was found");
    }

    /**
     * The VDIs backing a VM's disk VBDs (used to clean up a clone/copy/created VM's disks). VM.destroy
     * leaves VDIs behind, so callers destroy these explicitly afterward.
     */
    public static Set<VDI> diskVdis(Connection conn, VM vm) throws Exception {
        Set<VDI> vdis = new LinkedHashSet<>();
        for (VBD vbd : vm.getVBDs(conn))
            if (vbd.getType(conn) == Types.VbdType.DISK) vdis.add(vbd.getVDI(conn));
        return vdis;
    }

    /**
     * VM.destroy removes the VM record but leaves its disks behind; collect the owned VDIs first and
     * destroy them afterward. Works for a snapshot/checkpoint too - its "disks" are its own snapshot VDIs.
     */
    public static void destroyVmAndDisks(Connection conn, VM vm) throws Exception {
        Set<VDI> vdis = new LinkedHashSet<>(diskVdis(conn, vm));
        // A checkpoint (or a suspended VM) also owns a suspend image holding its memory, which no VBD
        // points at: destroy that as well.
        VDI suspendVdi = vm.getSuspendVDI(conn);
        if (!suspendVdi.toWireString().equals("OpaqueRef:NULL")) vdis.add(suspendVdi);
        vm.destroy(conn);
        for (VDI vdi : vdis) vdi.destroy(conn);
    }

    /**
     * Detach an SR from every host, then forget it. SR.forget refuses an SR that is still attached
     * (SR_HAS_PBD), so unplug its PBDs first. Forgetting drops the pool's record of the SR but leaves
     * the data on the storage itself.
     */
    public static void detachAndForgetSr(Connection conn, SR sr) throws Exception {
        for (PBD pbd : sr.getPBDs(conn)) {
            if (pbd.getCurrentlyAttached(conn)) pbd.unplug(conn);
        }
        sr.forget(conn);
    }

    /**
     * What xe vm-install does before VM.provision: a template's other_config["disks"] names sr="" for
     * every disk, and released xapi takes that literally and fails with UUID_INVALID. Rewrite each disk's
     * sr attribute to the pool's default SR first.
     */
    public static void provision(Connection conn, VM vm) throws Exception {
        String disks = vm.getOtherConfig(conn).get("disks");
        if (disks != null && disks.contains("sr=\"\"")) {
            SR defaultSr = Pool.getAllRecords(conn).values().iterator().next().defaultSR;
            vm.removeFromOtherConfig(conn, "disks");
            vm.addToOtherConfig(conn, "disks", disks.replace("sr=\"\"", "sr=\"" + defaultSr.getUuid(conn) + "\""));
        }
        vm.provision(conn);
    }

    /**
     * The first (from the end) field of a probe failure that looks like an XML fragment, or null.
     * SR.probe's deliberate failures surface as SrBackendFailure (status/stdout/stderr); other XenAPI
     * failures carry their raw params in errorDescription. Scan in reverse, like the Python reference.
     */
    private static String xmlFromFailure(Types.XenAPIException e) {
        java.util.List<String> candidates = new ArrayList<>();
        if (e instanceof Types.SrBackendFailure) {
            Types.SrBackendFailure sbf = (Types.SrBackendFailure) e;
            candidates.add(sbf.status);
            candidates.add(sbf.stdout);
            candidates.add(sbf.stderr);
        } else if (e.errorDescription != null) {
            candidates.addAll(java.util.Arrays.asList(e.errorDescription));
        }
        java.util.Collections.reverse(candidates);
        for (String c : candidates) {
            if (c != null && c.trim().startsWith("<")) return c;
        }
        return null;
    }

    /**
     * Return the XML a backend sends back on its deliberately-failing discovery probe. Discover iSCSI/HBA
     * LUNs by asking with an incomplete device-config on purpose: the backend can't create anything from
     * it yet, so it fails with an SR_BACKEND_FAILURE_&lt;n&gt; error whose params carry an XML fragment
     * describing what it found. A probe that unexpectedly SUCCEEDS means the device-config was already
     * complete - not the discovery prompt this helper looks for. Never probe by attempting SR.create
     * instead: on real storage a create that succeeds formats the LUN.
     */
    public static String probeForFailure(Connection conn, Host host, Map<String, String> deviceConfig,
            String smType) throws Exception {
        try {
            SR.probe(conn, host, deviceConfig, smType, new HashMap<String, String>());
        } catch (Types.XenAPIException e) {
            String xml = xmlFromFailure(e);
            if (xml != null) return xml;
            throw e;
        }
        throw new RuntimeException("SR.probe for " + smType + " succeeded without asking for more "
                + "information; check the target address");
    }

    /**
     * Parse an XML fragment and return its document root (used on the probe XML above).
     */
    public static org.w3c.dom.Document parseXml(String xml) throws Exception {
        return javax.xml.parsers.DocumentBuilderFactory.newInstance().newDocumentBuilder()
                .parse(new org.xml.sax.InputSource(new java.io.StringReader(xml)));
    }

    public static String firstTagText(org.w3c.dom.Element root, String tag) {
        org.w3c.dom.NodeList nodes = root.getElementsByTagName(tag);
        return nodes.getLength() > 0 ? nodes.item(0).getTextContent() : null;
    }

    /**
     * Is e the XenAPI error `code`? Check the text as well as the type: Java SDKs up to 26.22 throw an
     * error that has no parameters (HOST_STILL_BOOTING, HA_IS_ENABLED...) as BadServerResponse, whose text
     * is the JSON-RPC error, rather than as its typed exception.
     */
    private static boolean isError(Types.XenAPIException e, String code) {
        return String.valueOf(e).contains(code)
                || (e.errorDescription != null && e.errorDescription.length > 0 && code.equals(e.errorDescription[0]));
    }

    /**
     * Re-enable a host that has just come back. It reports itself live before xapi on it has finished
     * starting, and until then host.enable fails HOST_STILL_BOOTING - so retry that.
     */
    public static void enableWhenBooted(Connection conn, Host host) throws Exception {
        long deadline = System.currentTimeMillis() + 600_000;
        while (true) {
            try {
                host.enable(conn);
                return;
            } catch (Types.XenAPIException e) {
                boolean booting = e instanceof Types.HostStillBooting || isError(e, "HOST_STILL_BOOTING");
                if (!booting || System.currentTimeMillis() > deadline) throw e;
                Thread.sleep(10_000);
            }
        }
    }

    /**
     * Wait for a host to come back from a reboot (key "boot_time") or toolstack restart
     * ("agent_start_time"): until that other_config entry differs from `before` and the host is live.
     * Reconnects every time round, because the host restarting may be the coordinator this connection
     * talks to; returns the new Connection.
     */
    public static Connection waitForRestart(String url, String user, String password, String hostUuid,
            String key, String before) throws Exception {
        long deadline = System.currentTimeMillis() + 1_800_000;
        while (true) {
            try {
                Connection conn = connect(url, user, password);
                Host host = Host.getByUuid(conn, hostUuid);
                String now = host.getOtherConfig(conn).get(key);
                if (!java.util.Objects.equals(now, before) && host.getMetrics(conn).getLive(conn)) return conn;
                Session.logout(conn);
            } catch (Exception e) {
                // down, or xapi still starting
            }
            if (System.currentTimeMillis() > deadline)
                throw new RuntimeException("host " + hostUuid + " did not come back in time");
            Thread.sleep(10_000);
        }
    }

    /**
     * Build the URL for a given host's own address, keeping the scheme and port the caller originally
     * connected with (a host's management address carries no port of its own).
     */
    public static String hostUrl(String url, String address) throws Exception {
        URL parsed = new URL(url);
        int port = parsed.getPort();
        return parsed.getProtocol() + "://" + address + (port >= 0 ? ":" + port : "");
    }

    /**
     * Relocate every one of a (not-yet-started) VM's disks onto the given SR, the same VDI.poolMigrate
     * storage-migrate already demonstrates.
     */
    public static void moveDisksToSr(Connection conn, VM vm, SR sr) throws Exception {
        for (VDI vdi : diskVdis(conn, vm)) {
            if (!vdi.getSR(conn).equals(sr)) awaitTask(conn, vdi.poolMigrateAsync(conn, sr, new HashMap<String, String>()));
        }
    }

    /**
     * Wait for an Async task to finish, return its result and destroy it. A call that copies a disk runs
     * for many minutes - longer than the client waits for a reply (10 minutes by default) - so long
     * operations start the Async twin, which returns a Task at once, and poll that instead.
     */
    public static String awaitTask(Connection conn, Task task) throws Exception {
        try {
            while (task.getStatus(conn) == Types.TaskStatusType.PENDING) Thread.sleep(1000);
            if (task.getStatus(conn) != Types.TaskStatusType.SUCCESS)
                throw new RuntimeException(task.getNameLabel(conn) + " failed: " + task.getErrorInfo(conn));
            return task.getResult(conn).replace("<value>", "").replace("</value>", "").trim();
        } finally {
            task.destroy(conn);
        }
    }

    /**
     * A throwaway VM with a working guest OS: a copy of an existing VM that has one. Suspend, checkpoint,
     * live migration and clean shutdown all need the guest's cooperation: on a running VM with no PV
     * drivers xapi refuses them up front with VM_LACKS_FEATURE (a VM freshly cloned from a template has no
     * OS at all). So copy a VM that does have an OS and PV drivers, without disturbing it: snapshot it
     * (fine while it runs), clone the snapshot - a clone of a snapshot is a template - and provision that
     * into an ordinary VM. The snapshot is only needed for the clone, so it goes again straight away.
     */
    public static VM copyOfGuest(Connection conn, String sourceVmName, String newVmName) throws Exception {
        VM source = vmByName(conn, sourceVmName);
        VM snapshot = source.snapshot(conn, newVmName + "-source");
        VM vm = snapshot.createClone(conn, newVmName);
        provision(conn, vm);
        destroyVmAndDisks(conn, snapshot);
        return vm;
    }

    /**
     * Wait, after VM.start, until the guest's PV drivers have reported in. xapi only offers the
     * guest-dependent operations once the guest says it can do them, and getAllowedOperations is where it
     * says so: wait for CLEAN_SHUTDOWN to appear there (the same check that refuses it with
     * VM_LACKS_FEATURE beforehand). A booting OS takes a while. clean_shutdown in allowed_operations says
     * the guest can shut down; a Linux kernel offers that early in boot, before the agent runs (hot-plug
     * needs the agent, and suspend needs its emulated disk unplugged), so wait for the guest metrics to
     * report the PV drivers too.
     */
    private static boolean guestAgentReady(Connection conn, VM vm) throws Exception {
        if (!vm.getAllowedOperations(conn).contains(Types.VmOperations.CLEAN_SHUTDOWN)) return false;
        VMGuestMetrics metrics = vm.getGuestMetrics(conn);
        return !metrics.toWireString().equals("OpaqueRef:NULL") && metrics.getPVDriversDetected(conn);
    }

    public static void waitForGuestAgent(Connection conn, VM vm) throws Exception {
        waitForGuestAgent(conn, vm, 300, 2);
    }

    private static void waitForGuestAgent(Connection conn, VM vm, int timeoutSeconds, int intervalSeconds)
            throws Exception {
        long deadline = System.currentTimeMillis() + timeoutSeconds * 1000L;
        while (!guestAgentReady(conn, vm)) {
            if (System.currentTimeMillis() > deadline)
                throw new RuntimeException("the guest's PV drivers did not report in within " + timeoutSeconds
                        + "s; does the source VM have a guest OS with PV drivers (XenServer VM Tools)?");
            Thread.sleep(intervalSeconds * 1000L);
        }
    }

    /**
     * Introduce the pool's update repositories: the release's base packages (update=false) and its
     * update stream (update=true, which pool.syncUpdates needs - otherwise NO_REPOSITORY_ENABLED). A
     * real host checks the URLs (INVALID_BASE_URL for an unknown domain), so these are the XenServer
     * CDN's, e.g. https://repo.ops.xenserver.com/xs9/{base,normal}.
     */
    public static Set<Repository> introduceUpdateRepositories(Connection conn, String repoUrl,
            String sourceUrl) throws Exception {
        Set<Repository> repos = new LinkedHashSet<>();
        for (String stage : new String[] { "base", "normal" }) {
            repos.add(Repository.introduce(conn, "sdk-example-" + stage,
                    "SDK example " + stage + " repository", repoUrl + "/" + stage,
                    sourceUrl + "/" + stage, !stage.equals("base"), ""));
        }
        return repos;
    }
}
