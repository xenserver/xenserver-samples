using System.Collections.Generic;
using System.Linq;
using XenAPI;
using Console = System.Console; // XenAPI also defines a Console class

namespace XenServerWorkflows;

internal static partial class Workflows
{
    /// <summary>
    /// Create a scheduled-snapshot policy, attach a VM to it, run it on demand and watch the retention limit
    /// prune the oldest snapshot away.
    /// </summary>
    /// <example>
    /// <code>
    /// Workflows.SnapshotSchedule("https://xenserver", "root", password, "web-01");
    /// </code>
    /// </example>
    public static void SnapshotSchedule(string url, string user, string password,
        string vmName, string scheduleName = "sdk-example-schedule")
    {
        var session = Connect(url, user, password);
        var vmRef = VmByName(session, vmName);

        // retained_snapshots is the interesting field: the schedule prunes to it every time it runs.
        var vmssRef = VMSS.create(session, new VMSS
        {
            name_label = scheduleName,
            name_description = "Scheduled snapshots created by the SDK example",
            enabled = true,
            type = vmss_type.snapshot,
            frequency = vmss_frequency.daily,
            retained_snapshots = 2,
            schedule = new Dictionary<string, string> { ["hour"] = "2", ["min"] = "0" },
        });
        Console.WriteLine($"Created schedule: {VMSS.get_uuid(session, vmssRef)}");

        VM.set_snapshot_schedule(session, vmRef, vmssRef);
        Console.WriteLine($"Members:          {VMSS.get_VMs(session, vmssRef).Count}");

        // Run it three times against a retention of two: the oldest is pruned away. Compare against the
        // snapshots the VM already had, so only the schedule's own are counted (and tidied up below).
        var before = VM.get_snapshots(session, vmRef).ToHashSet();
        for (var i = 0; i < 3; i++) VMSS.snapshot_now(session, vmssRef);
        var kept = VM.get_snapshots(session, vmRef).Where(s => !before.Contains(s)).ToList();
        Console.WriteLine($"Snapshots kept:   {kept.Count} (retention 2)");

        // Tidy up: a schedule with VMs still on it cannot be destroyed (VMSS_HAS_VM), so take the VM off it
        // first. Destroying the schedule leaves the snapshots it took, so destroy those too, with their disks.
        VM.set_snapshot_schedule(session, vmRef, new XenRef<VMSS>(Helper.NullOpaqueRef));
        VMSS.destroy(session, vmssRef);
        foreach (var snapshot in kept) DestroyVmAndDisks(session, snapshot);
        Console.WriteLine("OK: snapshot-schedule");
        session.logout();
    }
}
