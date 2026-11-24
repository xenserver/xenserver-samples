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

import java.net.URI;
import java.util.ArrayList;
import java.util.Collections;
import java.util.HashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;

import static com.xenserver.samples.PoolConnection.connect;

/**
 * Small helpers several workflows share: finding objects by name, waiting for the guest agent, tidying
 * up what an example created.
 */
public final class Helpers {
    /**
     * What a reference field holds when it points at nothing: set a field to it to clear it. (To test a
     * reference, use its isNull().)
     */
    public static final String NULL_REF = "OpaqueRef:NULL";
    private Helpers() {
    }

    /**
     * Look up a template VM by its exact name (rather than picking an arbitrary one).
     */
    public static VM templateByName(Connection conn, String name) throws Exception {
        for (Map.Entry<VM, VM.Record> e : VM.getAllRecords(conn).entrySet())
            if (e.getValue().isATemplate && name.equals(e.getValue().nameLabel)) return e.getKey();
        throw new IllegalStateException("no template named '" + name + "' was found");
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
        throw new IllegalStateException("no VM named '" + name + "' was found");
    }

    /**
     * Look up an SR by its exact name (optionally requiring it to be shared).
     */
    public static SR srByName(Connection conn, String name, boolean shared) throws Exception {
        for (Map.Entry<SR, SR.Record> e : SR.getAllRecords(conn).entrySet())
            if (name.equals(e.getValue().nameLabel) && (!shared || e.getValue().shared)) return e.getKey();
        throw new IllegalStateException("no " + (shared ? "shared " : "") + "SR named '" + name + "' was found");
    }

    /**
     * The lowest-numbered of a VM's allowed VBD userdevice slots (getAllowedVBDDevices returns a Set, so
     * picking any element but the lowest would be arbitrary).
     */
    public static String lowestVBDDevice(Connection conn, VM vm) throws Exception {
        String lowest = null;
        for (String device : vm.getAllowedVBDDevices(conn))
            if (lowest == null || Integer.parseInt(device) < Integer.parseInt(lowest)) lowest = device;
        if (lowest == null) throw new IllegalStateException("the VM has no free VBD device slot");
        return lowest;
    }

    /**
     * The lowest-numbered of a VM's allowed VIF device slots (getAllowedVIFDevices returns a Set, so
     * picking any element but the lowest would be arbitrary).
     */
    public static String lowestVIFDevice(Connection conn, VM vm) throws Exception {
        String lowest = null;
        for (String device : vm.getAllowedVIFDevices(conn))
            if (lowest == null || Integer.parseInt(device) < Integer.parseInt(lowest)) lowest = device;
        if (lowest == null) throw new IllegalStateException("the VM has no free VIF device slot");
        return lowest;
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
        if (!suspendVdi.isNull()) vdis.add(suspendVdi);
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
        Collections.reverse(candidates);
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
        throw new IllegalStateException("SR.probe for " + smType + " succeeded without asking for more "
                + "information; check the target address");
    }

    /**
     * Parse an XML fragment and return its document root (used on the probe XML above).
     */
    public static org.w3c.dom.Document parseXml(String xml) throws Exception {
        // No DOCTYPE, so no external entities: a parser that follows them can be made to read local files or
        // make network requests (XXE) - so turn them off, as any code parsing XML should.
        javax.xml.parsers.DocumentBuilderFactory factory = javax.xml.parsers.DocumentBuilderFactory.newInstance();
        factory.setFeature("http://apache.org/xml/features/disallow-doctype-decl", true);
        return factory.newDocumentBuilder().parse(new org.xml.sax.InputSource(new java.io.StringReader(xml)));
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
                throw new IllegalStateException("host " + hostUuid + " did not come back in time");
            Thread.sleep(10_000);
        }
    }

    /**
     * Apply the pool's synced updates (hash, from Pool.syncUpdates) to one host, act on whatever
     * guidance applying them leaves pending, and return the host to service. Shared by ApplyUpdate, which
     * updates one host, and RollingPoolUpdate, which updates them all.
     *
     * <p>host.applyUpdates refuses a batch whose mandatory guidance needs an evacuation with
     * HOST_EVACUATION_IS_REQUIRED unless the host's resident VMs are moved off first - handle that
     * rather than assuming an update batch never asks for one: disable the host, evacuate it, and apply
     * again. Stay disabled afterwards - xapi refuses host.reboot on an enabled host (HOST_NOT_DISABLED) -
     * enableWhenBooted below returns the host to service once it is back, whether or not it needed a
     * restart at all. Then read the host's pending_guidances: a reboot or a toolstack restart returns
     * before it has actually happened, and if this host is the coordinator a reboot takes {@code conn}
     * with it - so note when the host last started, ask for the restart, and reconnect (waitForRestart)
     * until it reports a newer start and is live again. Resolve any pending mandatory host guidance
     * before returning - leaving it would otherwise block the next applyUpdates on this host with
     * HOST_PENDING_MANDATORY_GUIDANCES_NOT_EMPTY. Guidance that targets VMs instead of hosts (for
     * example restarting a VM) is not handled here.
     *
     * <p>{@code label} prefixes the progress lines this prints, e.g. the host's name followed by ": ".
     *
     * @return the Connection to keep using from here on - the same one, unless a restart replaced it.
     */
    public static Connection applyUpdatesToHost(Connection conn, String url, String user, String password,
            Host host, String hash, String label) throws Exception {
        String uuid = host.getUuid(conn);
        try {
            host.applyUpdates(conn, hash);
        } catch (Types.HostEvacuationIsRequired ex) {
            System.out.println("  " + label + "needs evacuating first; evacuating and retrying");
            host.disable(conn);
            host.evacuate(conn);
            host.applyUpdates(conn, hash);
            // Stay disabled: xapi refuses host.reboot on an enabled host (HOST_NOT_DISABLED), and
            // enableWhenBooted below returns the host to service once it is back.
        }
        Set<Types.UpdateGuidances> guidance = host.getPendingGuidances(conn);
        System.out.println("  " + label + "applied; pending guidance = " + guidance);
        boolean rebooting = guidance.contains(Types.UpdateGuidances.REBOOT_HOST);
        if (rebooting || guidance.contains(Types.UpdateGuidances.RESTART_TOOLSTACK)) {
            // Either restart returns before it has happened, and if this host is the coordinator it
            // takes this connection's session with it - so note when the host last started, restart it,
            // and reconnect until it reports a newer start and is live again.
            String key = rebooting ? "boot_time" : "agent_start_time";
            String before = host.getOtherConfig(conn).get(key);
            if (rebooting) {
                host.reboot(conn);
            } else {
                host.restartAgent(conn);
            }
            conn = waitForRestart(url, user, password, uuid, key, before);
        }
        // applyUpdates disables the host while it works (auto_enable: a restart puts it back) - with no
        // restart to do, nothing re-enables it. Return it to service either way.
        enableWhenBooted(conn, host);
        return conn;
    }

    /**
     * Build the URL for a given host's own address, keeping the scheme and port the caller originally
     * connected with (a host's management address carries no port of its own).
     */
    public static String hostUrl(String url, String address) {
        URI parsed = URI.create(url);
        int port = parsed.getPort();
        return parsed.getScheme() + "://" + address + (port >= 0 ? ":" + port : "");
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
                throw new IllegalStateException(task.getNameLabel(conn) + " failed: " + task.getErrorInfo(conn));
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
     * clean_shutdown in allowed_operations says the guest can shut down; a Linux kernel offers that early
     * in boot, before the agent runs (hot-plug needs the agent, and suspend needs its emulated disk
     * unplugged), so wait for the guest metrics to report the PV drivers too. xapi only offers the
     * guest-dependent operations once the guest says it can do them, and getAllowedOperations is where it
     * says so: wait for CLEAN_SHUTDOWN to appear there (the same check that refuses it with
     * VM_LACKS_FEATURE beforehand). A booting OS takes a while.
     */
    private static boolean guestAgentReady(Connection conn, VM vm) throws Exception {
        if (!vm.getAllowedOperations(conn).contains(Types.VmOperations.CLEAN_SHUTDOWN)) return false;
        VMGuestMetrics metrics = vm.getGuestMetrics(conn);
        return !metrics.isNull() && metrics.getPVDriversDetected(conn);
    }

    /**
     * Whether the guest agent has reported an IP address (VM_guest_metrics.networks).
     */
    private static boolean guestReportsIp(Connection conn, VM vm) throws Exception {
        VMGuestMetrics metrics = vm.getGuestMetrics(conn);
        if (metrics.isNull()) return false;
        return metrics.getNetworks(conn).keySet().stream()
                .anyMatch(key -> key.endsWith("/ip") || key.contains("/ipv4/"));
    }

    public static void waitForGuestAgent(Connection conn, VM vm) throws Exception {
        waitForGuestAgent(conn, vm, 30);
    }

    /** waitForGuestAgent with the settle chosen: none after a resume, where the guest isn't booting. */
    public static void waitForGuestAgent(Connection conn, VM vm, int settleSeconds) throws Exception {
        waitForGuestAgent(conn, vm, 300, 2, settleSeconds);
    }

    /**
     * Even with the PV drivers in, the guest may still be booting, and a guest asked to suspend mid-boot
     * (suspend, checkpoint, live migration) can fail to freeze a process that is busy starting up: it then
     * abandons the suspend without telling the host, which waits until VM_SUSPEND_TIMEOUT. xapi has no "boot
     * finished" signal, so also wait for the guest to report an IP address - a sign it has finished booting,
     * when it has a network - but that is only best effort: a guest with no network (no NIC, DHCP failure,
     * an isolated network) has still booted, so a missing IP address by the deadline is not a failure.
     */
    private static void waitForGuestAgent(Connection conn, VM vm, int timeoutSeconds, int intervalSeconds,
            int settleSeconds) throws Exception {
        long deadline = System.currentTimeMillis() + timeoutSeconds * 1000L;
        while (!guestAgentReady(conn, vm)) {
            if (System.currentTimeMillis() > deadline)
                throw new IllegalStateException("the guest did not finish booting (PV drivers) within "
                        + timeoutSeconds + "s; does the source VM have a guest OS with PV drivers (XenServer VM Tools)?");
            Thread.sleep(intervalSeconds * 1000L);
        }

        while (!guestReportsIp(conn, vm)) {
            if (System.currentTimeMillis() > deadline) {
                System.out.println("  no IP address reported within " + timeoutSeconds
                        + "s; carrying on (the guest has no network address)");
                break;
            }
            Thread.sleep(intervalSeconds * 1000L);
        }

        Thread.sleep(settleSeconds * 1000L);
    }

    /**
     * Introduce the pool's update repository: the release's update stream (update=true, which
     * pool.syncUpdates needs - otherwise NO_REPOSITORY_ENABLED). A real host checks the URL
     * (INVALID_BASE_URL for an unknown domain), so this is the XenServer CDN's, e.g.
     * https://repo.ops.xenserver.com/xs9/normal.
     */
    public static Repository introduceUpdateRepository(Connection conn, String repoUrl,
            String sourceUrl) throws Exception {
        return Repository.introduce(conn, "sdk-example-normal", "SDK example update repository",
                repoUrl + "/normal", sourceUrl + "/normal", true, "");
    }

    /** The update repository attachUpdateRepository introduced, and the pool's previous repositories. */
    public record AttachedRepository(Repository repo, Set<Repository> previous) {
    }

    /**
     * Get the pool ready to sync updates from {@code repoUrl}: check that HA and Workload Balancing are
     * off, then introduce the update repository and make it the pool's only one.
     *
     * <p>Host.applyUpdates refuses with HA_IS_ENABLED while HA is on, and the documentation also asks for
     * Workload Balancing to be switched off before you start updating - so check both up front and stop
     * rather than disabling either for you; turn them back on again once the update is done.
     * pool.syncUpdates needs at least one repository with update=true enabled (NO_REPOSITORY_ENABLED
     * otherwise).
     *
     * @return the repository and the pool's previous repositories, for detachUpdateRepository to put back.
     */
    public static AttachedRepository attachUpdateRepository(Connection conn, Pool pool, String repoUrl,
            String sourceUrl) throws Exception {
        if (pool.getHaEnabled(conn) || pool.getWlbEnabled(conn)) {
            throw new IllegalStateException("HA and Workload Balancing must both be off before updating the "
                    + "pool; disable them, run this again, then re-enable them once it finishes");
        }
        Repository repo = introduceUpdateRepository(conn, repoUrl, sourceUrl);
        Set<Repository> previous = pool.getRepositories(conn);
        try {
            pool.setRepositories(conn, Collections.singleton(repo));
        } catch (Exception ex) {
            repo.forget(conn);
            throw ex;
        }
        return new AttachedRepository(repo, previous);
    }

    /**
     * Undo attachUpdateRepository: give the pool back its previous repositories and forget the one it
     * introduced.
     */
    public static void detachUpdateRepository(Connection conn, Pool pool, AttachedRepository attached)
            throws Exception {
        pool.setRepositories(conn, attached.previous());
        attached.repo().forget(conn);
    }

    /**
     * Whether a VM is a guest: not a template, a snapshot or a host's control domain.
     */
    public static boolean isRealVm(VM.Record vm) {
        return !vm.isATemplate && !vm.isASnapshot && !vm.isControlDomain;
    }

    /**
     * Stop before updating if a host or VM still has mandatory guidance pending from an earlier update.
     * host.applyUpdates refuses a host that has some (HOST_PENDING_MANDATORY_GUIDANCES_NOT_EMPTY), part-way
     * through the update otherwise: act on it first - restart the host, its toolstack or the VM - and run the
     * update again.
     */
    public static void checkNoPendingGuidance(Connection conn) throws Exception {
        List<String> pending = new ArrayList<>();
        for (Host.Record h : Host.getAllRecords(conn).values()) {
            if (!h.pendingGuidances.isEmpty()) pending.add(h.nameLabel + ": " + guidanceList(h.pendingGuidances));
        }
        for (VM.Record vm : VM.getAllRecords(conn).values()) {
            if (isRealVm(vm) && !vm.pendingGuidances.isEmpty())
                pending.add(vm.nameLabel + ": " + guidanceList(vm.pendingGuidances));
        }
        if (!pending.isEmpty()) {
            Collections.sort(pending);
            throw new IllegalStateException("an earlier update's guidance is still pending - act on it first: "
                    + String.join("; ", pending));
        }
    }

    /**
     * Stop before changing anything if a host's VMs could not all move to another host:
     * getVmsWhichPreventEvacuation names them (for example a VM with a disk on the host's local storage, or
     * a pool with nowhere else to put them).
     */
    public static void checkHostsCanBeEvacuated(Connection conn, List<Host> hosts) throws Exception {
        for (Host host : hosts) {
            Map<VM, Set<String>> blocking = host.getVmsWhichPreventEvacuation(conn);
            if (!blocking.isEmpty()) {
                List<String> names = new ArrayList<>();
                for (VM vm : blocking.keySet()) names.add(vm.getNameLabel(conn));
                throw new IllegalStateException(host.getNameLabel(conn) + " cannot be evacuated: move or shut down "
                        + String.join(", ", names) + " first");
            }
        }
    }

    /**
     * The pool's hosts, coordinator first: the update documentation asks for the coordinator to be updated
     * before any other host.
     */
    public static List<Host> hostsCoordinatorFirst(Connection conn) throws Exception {
        Host master = Pool.getAll(conn).iterator().next().getMaster(conn);
        List<Host> hosts = new ArrayList<>();
        hosts.add(master);
        for (Host h : Host.getAll(conn)) {
            if (!h.equals(master)) hosts.add(h);
        }
        return hosts;
    }

    /**
     * Apply the synced updates (hash) to each host in turn, keeping the VMs running: disable the host so
     * nothing new starts there, evacuate it (live-migrating its VMs to the other hosts), and let
     * applyUpdatesToHost apply the updates, restart the host or its toolstack if the update asks for that,
     * and enable it again. The VMs stay where evacuation put them. Returns the connection to keep using from
     * here on - a restart of the coordinator replaces it.
     */
    public static Connection updateHosts(Connection conn, String url, String user, String password,
            List<Host> hosts, String hash) throws Exception {
        for (Host host : hosts) {
            System.out.println("Updating " + host.getNameLabel(conn) + ": moving its VMs to the rest of the pool");
            host.disable(conn);
            host.evacuate(conn);
            conn = applyUpdatesToHost(conn, url, user, password, host, hash, "");
        }
        return conn;
    }

    /**
     * Print the guidance updating left pending for VMs - restart_vm or restart_device_model, for a VM to start
     * using what was updated. Acting on it restarts the VM, which is its owner's call rather than the
     * update's, so this only reports it.
     */
    public static void reportVmGuidance(Connection conn) throws Exception {
        List<String> pending = new ArrayList<>();
        for (VM.Record vm : VM.getAllRecords(conn).values()) {
            if (isRealVm(vm) && !vm.pendingGuidances.isEmpty())
                pending.add(vm.nameLabel + ": " + guidanceList(vm.pendingGuidances));
        }
        Collections.sort(pending);
        System.out.println("VM guidance pending: " + (pending.isEmpty() ? "none" : String.join("; ", pending)));
    }

    private static String guidanceList(Set<Types.UpdateGuidances> guidance) {
        List<String> names = new ArrayList<>();
        for (Types.UpdateGuidances g : guidance) names.add(g.toString());
        return String.join(", ", names);
    }
}
