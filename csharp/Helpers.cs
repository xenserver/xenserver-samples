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
    internal static string TemplateByName(Session session, string name) =>
        VM.get_all_records(session).First(kv => kv.Value.is_a_template && kv.Value.name_label == name)
            .Key.opaque_ref;

    /// <summary>
    /// Look up a guest VM (not a template, control domain or snapshot) by its exact name.
    /// </summary>
    internal static string VmByName(Session session, string name) =>
        VM.get_all_records(session).First(kv => !kv.Value.is_a_template && !kv.Value.is_control_domain
            && !kv.Value.is_a_snapshot && kv.Value.name_label == name).Key.opaque_ref;

    /// <summary>
    /// Look up an SR by its exact name (optionally requiring it to be shared).
    /// </summary>
    internal static string SrByName(Session session, string name, bool shared = false) =>
        SR.get_all_records(session).First(kv => kv.Value.name_label == name && (!shared || kv.Value.shared))
            .Key.opaque_ref;

    /// <summary>
    /// Detach an SR from every host, then forget it. SR.forget refuses an SR that is still attached
    /// (SR_HAS_PBD), so unplug its PBDs first. Forgetting drops the pool's record of the SR but leaves
    /// the data on the storage itself.
    /// </summary>
    internal static void DetachAndForgetSr(Session session, string sr)
    {
        foreach (var pbd in SR.get_PBDs(session, sr))
            if (PBD.get_currently_attached(session, pbd.opaque_ref))
                PBD.unplug(session, pbd.opaque_ref);
        SR.forget(session, sr);
    }

    /// <summary>
    /// VM.provision, after filling in the SR for every disk the template describes. A template's
    /// other_config["disks"] carries each disk's SR as sr="" (empty); a real host takes that literally and
    /// VM.provision fails with UUID_INVALID, so the caller has to rewrite it to the pool's default SR
    /// first — exactly what `xe vm-install` does before calling VM.provision itself.
    /// </summary>
    internal static void Provision(Session session, string vm)
    {
        if (VM.get_other_config(session, vm).TryGetValue("disks", out var disksXml))
        {
            var defaultSr = Pool.get_default_SR(session, Pool.get_all(session).First().opaque_ref).opaque_ref;
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
    internal static string ProbeForFailure(Session session, string host,
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
        throw new Exception($"SR.probe for {smType} succeeded without asking for more information; " +
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
                var host = Host.get_by_uuid(session, hostUuid).opaque_ref;
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
            if (DateTime.UtcNow > deadline) throw new Exception($"host {hostUuid} did not come back in time");
            System.Threading.Thread.Sleep(intervalSeconds * 1000);
        }
    }

    /// <summary>
    /// Re-enable a host that has just come back. It reports itself live before xapi on it has finished
    /// starting, and until then Host.enable fails HOST_STILL_BOOTING - so retry that.
    /// </summary>
    internal static void EnableWhenBooted(Session session, string host, int timeoutSeconds = 600,
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
    /// Relocate every one of a (not-yet-started) VM's disks onto the given SR, the same VDI.pool_migrate
    /// storage-migrate already demonstrates.
    /// </summary>
    internal static void MoveDisksToSr(Session session, string vm, string srRef)
    {
        foreach (var vdi in DiskVdis(session, vm))
            if (VDI.get_SR(session, vdi).opaque_ref != srRef)
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
    internal static string CopyOfGuest(Session session, string sourceVmName, string newVmName)
    {
        var source = VmByName(session, sourceVmName);
        var snapshot = VM.snapshot(session, source, newVmName + "-source").opaque_ref;
        var vm = VM.clone(session, snapshot, newVmName).opaque_ref;
        Provision(session, vm);
        DestroyVmAndDisks(session, snapshot);
        return vm;
    }

    /// <summary>
    /// Wait, after VM.start, until the guest's PV drivers have reported in. xapi only offers the
    /// guest-dependent operations once the guest says it can do them, and allowed_operations is where
    /// it says so: wait for clean_shutdown to appear there (the same check that refuses it with
    /// VM_LACKS_FEATURE beforehand). A booting OS takes a while.
    /// </summary>
    internal static void WaitForGuestAgent(Session session, string vm, int timeoutSeconds = 300,
        int intervalSeconds = 2)
    {
        // clean_shutdown in allowed_operations says the guest can shut down; a Linux kernel offers that early
        // in boot, before the agent runs (hot-plug needs the agent, and suspend needs its emulated disk
        // unplugged), so wait for the guest metrics to report the PV drivers too.
        bool Ready()
        {
            if (!VM.get_allowed_operations(session, vm).Contains(vm_operations.clean_shutdown)) return false;
            var metrics = VM.get_guest_metrics(session, vm);
            return metrics.opaque_ref != "OpaqueRef:NULL"
                   && VM_guest_metrics.get_PV_drivers_detected(session, metrics.opaque_ref);
        }

        var deadline = DateTime.UtcNow.AddSeconds(timeoutSeconds);
        while (!Ready())
        {
            if (DateTime.UtcNow > deadline)
                throw new Exception($"the guest's PV drivers did not report in within {timeoutSeconds}s; " +
                    "does the source VM have a guest OS with PV drivers (XenServer VM Tools)?");
            System.Threading.Thread.Sleep(intervalSeconds * 1000);
        }
    }

    /// <summary>The VDIs backing a VM's disk VBDs (used to clean up a full copy's independent
    /// disks).</summary>
    internal static List<string> DiskVdis(Session session, string vmRef)
    {
        var vdis = new List<string>();
        foreach (var vbdRef in VM.get_VBDs(session, vmRef))
        {
            if (VBD.get_type(session, vbdRef.opaque_ref) != vbd_type.Disk) continue;
            var vdi = VBD.get_VDI(session, vbdRef.opaque_ref).opaque_ref;
            if (vdi != "OpaqueRef:NULL") vdis.Add(vdi);
        }
        return vdis;
    }

    /// <summary>
    /// VM.destroy leaves a VM's (or snapshot's/template's) disks behind; this collects them first and
    /// destroys them afterwards, the way delete-vm does for a VM it created.
    /// </summary>
    internal static void DestroyVmAndDisks(Session session, string vm)
    {
        var vdis = DiskVdis(session, vm);
        // A checkpoint (or a suspended VM) also owns a suspend image holding its memory, which no VBD
        // points at: destroy that as well.
        var suspendVdi = VM.get_suspend_VDI(session, vm).opaque_ref;
        if (suspendVdi != "OpaqueRef:NULL") vdis.Add(suspendVdi);
        VM.destroy(session, vm);
        foreach (var vdi in vdis) VDI.destroy(session, vdi);
    }

    /// <summary>
    /// Introduce the pool's update repositories: the release's base packages (update=false) and its
    /// update stream (update=true, which pool.sync_updates needs - otherwise NO_REPOSITORY_ENABLED). A
    /// real host checks the URLs (INVALID_BASE_URL for an unknown domain), so these are the XenServer
    /// CDN's, e.g. https://repo.ops.xenserver.com/xs9/{base,normal}.
    /// </summary>
    internal static List<XenRef<Repository>> IntroduceUpdateRepositories(Session session, string repoUrl,
        string sourceUrl) =>
        new[] { "base", "normal" }.Select(stage => new XenRef<Repository>(Repository.introduce(session,
            $"sdk-example-{stage}", $"SDK example {stage} repository",
            $"{repoUrl}/{stage}", $"{sourceUrl}/{stage}", stage != "base", "").opaque_ref)).ToList();

    /// <summary>An HTTP client that accepts the host's self-signed certificate, as Connect does.</summary>
    internal static HttpClient InsecureHttpClient() =>
        new(new HttpClientHandler { ServerCertificateCustomValidationCallback = (_, _, _, _) => true })
        {
            Timeout = TimeSpan.FromMinutes(5),
        };

    internal static bool HostLive(Session session, string host) =>
        Host_metrics.get_live(session, Host.get_metrics(session, host).opaque_ref);
}
