// Small helpers several workflows share: finding objects by name, waiting for the guest agent,
// tidying up what an example created.

using System;
using System.Collections.Generic;
using System.Linq;
using System.Net.Http;
using System.Xml.Linq;
using XenAPI;

namespace XenServerWorkflows;

internal static partial class Workflows
{
    /// <summary>
    /// Look up a template VM by its exact name (rather than picking an arbitrary one).
    /// </summary>
    internal static XenRef<VM> TemplateByName(Session session, string name) =>
        VM.get_all_records(session).First(kv => kv.Value.is_a_template && kv.Value.name_label == name).Key;

    /// <summary>
    /// Look up a guest VM (not a template, control domain or snapshot) by its exact name.
    /// </summary>
    internal static XenRef<VM> VmByName(Session session, string name) =>
        VM.get_all_records(session).First(kv => !kv.Value.is_a_template && !kv.Value.is_control_domain
            && !kv.Value.is_a_snapshot && kv.Value.name_label == name).Key;

    /// <summary>
    /// Look up an SR by its exact name (optionally requiring it to be shared).
    /// </summary>
    internal static XenRef<SR> SrByName(Session session, string name, bool shared = false) =>
        SR.get_all_records(session).First(kv => kv.Value.name_label == name && (!shared || kv.Value.shared)).Key;

    /// <summary>
    /// Detach an SR from every host, then forget it. SR.forget refuses an SR that is still attached
    /// (SR_HAS_PBD), so unplug its PBDs first. Forgetting drops the pool's record of the SR but leaves
    /// the data on the storage itself.
    /// </summary>
    internal static void DetachAndForgetSr(Session session, XenRef<SR> sr)
    {
        foreach (var pbd in SR.get_PBDs(session, sr))
            if (PBD.get_currently_attached(session, pbd))
                PBD.unplug(session, pbd);
        SR.forget(session, sr);
    }

    /// <summary>
    /// VM.provision, after filling in the SR for every disk the template describes. A template's
    /// other_config["disks"] carries each disk's SR as sr="" (empty); a real host takes that literally and
    /// VM.provision fails with UUID_INVALID, so the caller has to rewrite it to the pool's default SR
    /// first — exactly what `xe vm-install` does before calling VM.provision itself.
    /// </summary>
    internal static void Provision(Session session, XenRef<VM> vm)
    {
        if (VM.get_other_config(session, vm).TryGetValue("disks", out var disksXml))
        {
            var defaultSr = Pool.get_default_SR(session, Pool.get_all(session).First());
            var doc = XDocument.Parse(disksXml);
            foreach (var disk in doc.Root!.Elements("disk"))
                disk.SetAttributeValue("sr", SR.get_uuid(session, defaultSr));

            VM.remove_from_other_config(session, vm, "disks");
            VM.add_to_other_config(session, vm, "disks", doc.ToString(SaveOptions.DisableFormatting));
        }
        VM.provision(session, vm);
    }

    /// <summary>The first (from the end) Failure detail that looks like an XML fragment, or null.</summary>
    internal static string XmlFromFailure(Failure f) =>
        f.ErrorDescription.AsEnumerable().Reverse()
            .FirstOrDefault(d => !string.IsNullOrEmpty(d) && d.TrimStart().StartsWith("<"));

    /// <summary>
    /// Return the XML a backend sends back on its deliberately-failing discovery probe. Discover iSCSI/HBA
    /// LUNs by asking with an incomplete device-config on purpose: the backend can't create anything from it
    /// yet, so it fails with an SR_BACKEND_FAILURE_&lt;n&gt; error whose params carry an XML fragment
    /// describing what it found. Never probe by attempting SR.create instead: on real storage a create that
    /// unexpectedly succeeds formats the LUN.
    /// </summary>
    internal static string ProbeForFailure(Session session, XenRef<Host> host,
        Dictionary<string, string> deviceConfig, string smType)
    {
        try
        {
            SR.probe(session, host, deviceConfig, smType, new Dictionary<string, string>());
        }
        catch (Failure f)
        {
            var xml = XmlFromFailure(f);
            if (xml != null) return xml;
            throw;
        }
        throw new InvalidOperationException($"SR.probe for {smType} succeeded without asking for more information; " +
                            "check the target address");
    }

    /// <summary>
    /// Wait for a host to come back from a reboot (key "boot_time") or toolstack restart
    /// ("agent_start_time"): until that other_config entry differs from <paramref name="before"/> and the
    /// host is live. Reconnects every time round, because the host restarting may be the coordinator this
    /// session talks to; returns the new session.
    /// </summary>
    internal static Session WaitForRestart(string url, string user, string password, string hostUuid,
        string key, string before, int timeoutSeconds = 1800, int intervalSeconds = 10)
    {
        var deadline = DateTime.UtcNow.AddSeconds(timeoutSeconds);
        while (true)
        {
            try
            {
                var session = Connect(url, user, password);
                var host = Host.get_by_uuid(session, hostUuid);
                var otherConfig = Host.get_other_config(session, host);
                var value = otherConfig.TryGetValue(key, out var v) ? v : null;
                if (value != before && HostLive(session, host))
                    return session;
                session.logout();
            }
            catch (Exception)
            {
                // down, or xapi still starting
            }
            if (DateTime.UtcNow > deadline) throw new InvalidOperationException($"host {hostUuid} did not come back in time");
            System.Threading.Thread.Sleep(intervalSeconds * 1000);
        }
    }

    /// <summary>
    /// Re-enable a host that has just come back. It reports itself live before xapi on it has finished
    /// starting, and until then Host.enable fails HOST_STILL_BOOTING - so retry that.
    /// </summary>
    internal static void EnableWhenBooted(Session session, XenRef<Host> host, int timeoutSeconds = 600,
        int intervalSeconds = 10)
    {
        var deadline = DateTime.UtcNow.AddSeconds(timeoutSeconds);
        while (true)
        {
            try
            {
                Host.enable(session, host);
                return;
            }
            catch (Failure e)
            {
                if (e.ErrorDescription[0] != "HOST_STILL_BOOTING" || DateTime.UtcNow > deadline) throw;
                System.Threading.Thread.Sleep(intervalSeconds * 1000);
            }
        }
    }

    /// <summary>
    /// Apply the pool's synced updates (<paramref name="hash"/>, from Pool.sync_updates) to one host, act
    /// on whatever guidance applying them leaves pending, and return the host to service. Shared by
    /// apply-update, which updates one host, and rolling-pool-update, which updates them all.
    /// </summary>
    /// <remarks>
    /// Host.apply_updates refuses a batch whose mandatory guidance needs an evacuation with
    /// HOST_EVACUATION_IS_REQUIRED unless the host's resident VMs are moved off first - handle that
    /// rather than assuming an update batch never asks for one: disable the host, evacuate it, and apply
    /// again. Stay disabled afterwards - xapi refuses Host.reboot on an enabled host (HOST_NOT_DISABLED) -
    /// EnableWhenBooted below returns the host to service once it is back, whether or not it needed a
    /// restart at all. Then read the host's pending_guidances: a reboot or a toolstack restart returns
    /// before it has actually happened, and if this host is the coordinator a reboot takes
    /// <paramref name="session"/> with it - so note when the host last started, ask for the restart, and
    /// reconnect (WaitForRestart) until it reports a newer start and is live again. Resolve any pending
    /// mandatory host guidance before returning - leaving it would otherwise block the next apply_updates
    /// on this host with HOST_PENDING_MANDATORY_GUIDANCES_NOT_EMPTY. Guidance that targets VMs instead of
    /// hosts (for example restarting a VM) is not handled here.
    /// </remarks>
    /// <param name="label">Prefixes the progress lines this prints, e.g. the host's name followed by
    /// ": ".</param>
    /// <returns>The session to keep using from here on - the same one, unless a restart replaced it.</returns>
    internal static Session ApplyUpdatesToHost(Session session, string url, string user, string password,
        XenRef<Host> hostRef, string hash, string label = "")
    {
        var hostUuid = Host.get_uuid(session, hostRef);
        try
        {
            Host.apply_updates(session, hostRef, hash);
        }
        catch (Failure f) when (f.ErrorDescription[0] == "HOST_EVACUATION_IS_REQUIRED")
        {
            System.Console.WriteLine($"  {label}needs evacuating first; evacuating and retrying");
            Host.disable(session, hostRef);
            Host.evacuate(session, hostRef);
            Host.apply_updates(session, hostRef, hash);
            // Stay disabled: xapi refuses host.reboot on an enabled host (HOST_NOT_DISABLED), and
            // EnableWhenBooted below returns the host to service once it is back.
        }
        var guidance = Host.get_pending_guidances(session, hostRef);
        System.Console.WriteLine($"  {label}applied; pending guidance = [{string.Join(", ", guidance)}]");
        // Modern xapi (>=23.18.0) doesn't reboot a host for you: it only records pending_guidances, so
        // only reboot (or restart the toolstack) when the applied batch actually asks for it.
        if (guidance.Contains(update_guidances.reboot_host) ||
            guidance.Contains(update_guidances.restart_toolstack))
        {
            // Either restart returns before it has happened, and if this host is the coordinator it
            // takes this session with it - so note when the host last started, restart it, and
            // reconnect until it reports a newer start and is live again.
            var rebooting = guidance.Contains(update_guidances.reboot_host);
            var key = rebooting ? "boot_time" : "agent_start_time";
            Host.get_other_config(session, hostRef).TryGetValue(key, out var before);
            if (rebooting)
                Host.reboot(session, hostRef);
            else
                Host.restart_agent(session, hostRef);
            session = WaitForRestart(url, user, password, hostUuid, key, before);
        }
        // apply_updates disables the host while it works (auto_enable: a restart puts it back) - with
        // no restart to do, nothing re-enables it. Return it to service either way.
        EnableWhenBooted(session, hostRef);
        return session;
    }

    /// <summary>
    /// Relocate every one of a (not-yet-started) VM's disks onto the given SR, the same VDI.pool_migrate
    /// storage-migrate already demonstrates.
    /// </summary>
    internal static void MoveDisksToSr(Session session, XenRef<VM> vm, XenRef<SR> srRef)
    {
        foreach (var vdi in DiskVdis(session, vm))
            if (!VDI.get_SR(session, vdi).Equals(srRef))
                AwaitTask(session, VDI.async_pool_migrate(session, vdi, srRef, new Dictionary<string, string>()));
    }

    /// <summary>
    /// Wait for an async_* task to finish, return its result and destroy it. A call that copies a disk
    /// runs for many minutes, and an HTTP request held open that long tends to be dropped by the network
    /// (SocketException 10060) however long the client is willing to wait, so long operations start the
    /// async_ twin, which returns a Task at once, and poll that instead.
    /// </summary>
    internal static string AwaitTask(Session session, XenRef<Task> task)
    {
        try
        {
            while (Task.get_status(session, task) == task_status_type.pending)
                System.Threading.Thread.Sleep(1000);
            if (Task.get_status(session, task) != task_status_type.success)
                throw new Failure(Task.get_error_info(session, task));
            return Task.get_result(session, task).Replace("<value>", "").Replace("</value>", "").Trim();
        }
        finally
        {
            Task.destroy(session, task);
        }
    }

    /// <summary>
    /// A throwaway VM with a working guest OS: a copy of an existing VM that has one. Suspend,
    /// checkpoint, live migration and clean shutdown all need the guest's cooperation: on a running VM
    /// with no PV drivers xapi refuses them up front with VM_LACKS_FEATURE (a VM freshly cloned from a
    /// template has no OS at all). So copy a VM that does have an OS and PV drivers, without disturbing
    /// it: snapshot it (fine while it runs), clone the snapshot - a clone of a snapshot is a template -
    /// and provision that into an ordinary VM. The snapshot is only needed for the clone, so it goes
    /// again straight away.
    /// </summary>
    internal static XenRef<VM> CopyOfGuest(Session session, string sourceVmName, string newVmName)
    {
        var source = VmByName(session, sourceVmName);
        var snapshot = VM.snapshot(session, source, newVmName + "-source");
        var vm = VM.clone(session, snapshot, newVmName);
        Provision(session, vm);
        DestroyVmAndDisks(session, snapshot);
        return vm;
    }

    /// <summary>
    /// Wait, after VM.start, until the guest's PV drivers have reported in, then settle. xapi only offers
    /// the guest-dependent operations once the guest says it can do them, and allowed_operations is where
    /// it says so: wait for clean_shutdown to appear there (the same check that refuses it with
    /// VM_LACKS_FEATURE beforehand). A booting OS takes a while.
    /// </summary>
    internal static void WaitForGuestAgent(Session session, XenRef<VM> vm, int timeoutSeconds = 300,
        int intervalSeconds = 2, int settleSeconds = 30)
    {
        // clean_shutdown in allowed_operations says the guest can shut down; a Linux kernel offers that early
        // in boot, before the agent runs (hot-plug needs the agent, and suspend needs its emulated disk
        // unplugged), so wait for the guest metrics to report the PV drivers too.
        bool Ready()
        {
            if (!VM.get_allowed_operations(session, vm).Contains(vm_operations.clean_shutdown)) return false;
            var metrics = VM.get_guest_metrics(session, vm);
            return !Helper.IsNullOrEmptyOpaqueRef(metrics)
                   && VM_guest_metrics.get_PV_drivers_detected(session, metrics);
        }

        // Even then the guest may still be booting, and a guest asked to suspend mid-boot (suspend,
        // checkpoint, live migration) can fail to freeze a process that is busy starting up: it then abandons
        // the suspend without telling the host, which waits until VM_SUSPEND_TIMEOUT. xapi has no "boot
        // finished" signal, so also wait for the guest to report an IP address - a sign it has finished
        // booting, when it has a network - but that is only best effort: a guest with no network (no NIC,
        // DHCP failure, an isolated network) has still booted, so a missing IP address by the deadline is
        // not a failure.
        bool HasIp()
        {
            var metrics = VM.get_guest_metrics(session, vm);
            return !Helper.IsNullOrEmptyOpaqueRef(metrics) && VM_guest_metrics.get_networks(session, metrics)
                .Keys.Any(key => key.EndsWith("/ip") || key.Contains("/ipv4/"));
        }

        var deadline = DateTime.UtcNow.AddSeconds(timeoutSeconds);
        while (!Ready())
        {
            if (DateTime.UtcNow > deadline)
                throw new InvalidOperationException("the guest did not finish booting (PV drivers) within " +
                    $"{timeoutSeconds}s; does the source VM have a guest OS with PV drivers (XenServer VM Tools)?");
            System.Threading.Thread.Sleep(intervalSeconds * 1000);
        }

        while (!HasIp())
        {
            if (DateTime.UtcNow > deadline)
            {
                System.Console.WriteLine($"  no IP address reported within {timeoutSeconds}s; carrying on " +
                    "(the guest has no network address)");
                break;
            }
            System.Threading.Thread.Sleep(intervalSeconds * 1000);
        }

        System.Threading.Thread.Sleep(settleSeconds * 1000);
    }

    /// <summary>The VDIs backing a VM's disk VBDs (used to clean up a full copy's independent
    /// disks).</summary>
    internal static List<XenRef<VDI>> DiskVdis(Session session, XenRef<VM> vmRef)
    {
        var vdis = new List<XenRef<VDI>>();
        foreach (var vbdRef in VM.get_VBDs(session, vmRef))
        {
            if (VBD.get_type(session, vbdRef) != vbd_type.Disk) continue;
            var vdi = VBD.get_VDI(session, vbdRef);
            if (!Helper.IsNullOrEmptyOpaqueRef(vdi)) vdis.Add(vdi);
        }
        return vdis;
    }

    /// <summary>
    /// VM.destroy leaves a VM's (or snapshot's/template's) disks behind; this collects them first and
    /// destroys them afterwards, the way delete-vm does for a VM it created.
    /// </summary>
    internal static void DestroyVmAndDisks(Session session, XenRef<VM> vm)
    {
        var vdis = DiskVdis(session, vm);
        // A checkpoint (or a suspended VM) also owns a suspend image holding its memory, which no VBD
        // points at: destroy that as well.
        var suspendVdi = VM.get_suspend_VDI(session, vm);
        if (!Helper.IsNullOrEmptyOpaqueRef(suspendVdi)) vdis.Add(suspendVdi);
        VM.destroy(session, vm);
        foreach (var vdi in vdis) VDI.destroy(session, vdi);
    }

    /// <summary>
    /// Introduce the pool's update repository: the release's update stream (update=true, which
    /// pool.sync_updates needs - otherwise NO_REPOSITORY_ENABLED). A real host checks the URL
    /// (INVALID_BASE_URL for an unknown domain), so this is the XenServer CDN's, e.g.
    /// https://repo.ops.xenserver.com/xs9/normal.
    /// </summary>
    internal static XenRef<Repository> IntroduceUpdateRepository(Session session, string repoUrl,
        string sourceUrl) =>
        Repository.introduce(session, "sdk-example-normal", "SDK example update repository",
            $"{repoUrl}/normal", $"{sourceUrl}/normal", true, "");

    /// <summary>
    /// Get the pool ready to sync updates from <paramref name="repoUrl"/>: check that HA and Workload
    /// Balancing are off, then introduce the update repository and make it the pool's only one.
    /// </summary>
    /// <remarks>
    /// Host.apply_updates refuses with HA_IS_ENABLED while HA is on, and the documentation also asks for
    /// Workload Balancing to be switched off before you start updating - so check both up front and stop
    /// rather than disabling either for you; turn them back on again once the update is done.
    /// Pool.sync_updates needs at least one repository with update=true enabled (NO_REPOSITORY_ENABLED
    /// otherwise).
    /// </remarks>
    /// <returns>The repository and the pool's previous repositories, for DetachUpdateRepository to put
    /// back.</returns>
    internal static (XenRef<Repository> Repo, List<XenRef<Repository>> Previous) AttachUpdateRepository(
        Session session, XenRef<Pool> pool, string repoUrl, string sourceUrl)
    {
        if (Pool.get_ha_enabled(session, pool) || Pool.get_wlb_enabled(session, pool))
            throw new InvalidOperationException("HA and Workload Balancing must both be off before updating the pool; " +
                                                "disable them, run this again, then re-enable them once it finishes");
        var repo = IntroduceUpdateRepository(session, repoUrl, sourceUrl);
        var previous = Pool.get_repositories(session, pool);
        try
        {
            Pool.set_repositories(session, pool, new List<XenRef<Repository>> { repo });
        }
        catch
        {
            Repository.forget(session, repo);
            throw;
        }
        return (repo, previous);
    }

    /// <summary>
    /// Undo AttachUpdateRepository: give the pool back its previous repositories and forget the one it
    /// introduced.
    /// </summary>
    internal static void DetachUpdateRepository(Session session, XenRef<Pool> pool, XenRef<Repository> repo,
        List<XenRef<Repository>> previous)
    {
        Pool.set_repositories(session, pool, previous);
        Repository.forget(session, repo);
    }

    /// <summary>An HTTP client that accepts the host's self-signed certificate, as Connect does.</summary>
    internal static HttpClient InsecureHttpClient() =>
        new(new HttpClientHandler { ServerCertificateCustomValidationCallback = (_, _, _, _) => true })
        {
            Timeout = TimeSpan.FromMinutes(5),
        };

    internal static bool HostLive(Session session, XenRef<Host> host) =>
        Host_metrics.get_live(session, Host.get_metrics(session, host));

    /// <summary>
    /// Build the URL for a given host's own address, keeping the scheme and port the caller originally
    /// connected with (a host's management address carries no port of its own). Needed anywhere a
    /// workflow does raw HTTP against a SPECIFIC host rather than the pool's connection URL - a host
    /// answers a direct HTTP request only for itself, with no forwarding to another pool member.
    /// </summary>
    internal static string HostUrl(string url, string address)
    {
        var uri = new Uri(url);
        var port = uri.IsDefaultPort ? "" : $":{uri.Port}";
        return $"{uri.Scheme}://{address}{port}";
    }
}
