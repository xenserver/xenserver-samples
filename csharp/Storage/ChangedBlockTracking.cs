using System;
using System.Linq;
using XenAPI;
using Console = System.Console; // XenAPI also defines a Console class

namespace XenServerWorkflows;

internal static partial class Workflows
{
    /// <summary>
    /// Walk an incremental backup: turn on changed block tracking, snapshot twice, ask the server which
    /// blocks differ, then release the older snapshot's data while keeping the change metadata the next
    /// incremental needs.
    /// </summary>
    /// <example>
    /// <code>
    /// Workflows.ChangedBlockTracking("https://xenserver", "root", password);
    /// </code>
    /// </example>
    public static void ChangedBlockTracking(string url, string user, string password)
    {
        var session = Connect(url, user, password);

        var vm = VM.get_all_records(session).First(kv =>
            !kv.Value.is_a_template && !kv.Value.is_control_domain && !kv.Value.is_a_snapshot &&
            kv.Value.VBDs.Count > 0);
        Console.WriteLine($"Backing up {vm.Value.name_label}");

        // CBT is switched on for the VM's own disk, and every snapshot taken from then on inherits it.
        // It can't be switched on for a snapshot's disk after the fact (OPERATION_NOT_ALLOWED).
        var live = FirstDisk(session, vm.Key.opaque_ref);
        var wasEnabled = VDI.get_cbt_enabled(session, live);
        if (!wasEnabled) VDI.enable_cbt(session, live);

        var first = VM.snapshot(session, vm.Key.opaque_ref, "cbt-backup-1");
        var second = VM.snapshot(session, vm.Key.opaque_ref, "cbt-backup-2");
        var vdiFrom = FirstDisk(session, first.opaque_ref);
        var vdiTo = FirstDisk(session, second.opaque_ref);

        // One bit per 64 KiB block, base64-encoded; bit N set means block N changed. A real backup reads
        // only those blocks, over NBD.
        var bitmap = Convert.FromBase64String(VDI.list_changed_blocks(session, vdiFrom, vdiTo));
        var changed = bitmap.Sum(b => System.Numerics.BitOperations.PopCount(b));
        Console.WriteLine($"  {changed} blocks of {bitmap.Length * 8} changed "
                          + $"({changed * 64 / 1024.0:F1} MiB to copy, not "
                          + $"{VDI.get_virtual_size(session, vdiTo) / (1024.0 * 1024):F1} MiB)");

        // Release the older snapshot's blocks but keep its change metadata, so the next incremental can
        // still diff against it. data_destroy refuses a disk that a VM still uses (VDI_IN_USE), so drop the
        // older snapshot's VM record first, as a backup tool does. The VDI record stays; its type changes.
        VM.destroy(session, first.opaque_ref);
        VDI.data_destroy(session, vdiFrom);
        Console.WriteLine($"  older snapshot is now type={VDI.get_type(session, vdiFrom)}, "
                          + $"still cbt_enabled={VDI.get_cbt_enabled(session, vdiFrom)}");

        // Tidy up: the newer snapshot and its disk, the metadata-only VDI, and CBT on the VM's own disk
        // if this example switched it on.
        DestroyVmAndDisks(session, second.opaque_ref);
        VDI.destroy(session, vdiFrom);
        if (!wasEnabled) VDI.disable_cbt(session, live);
        Console.WriteLine("OK: changed-block-tracking");
        session.logout();
    }

    /// <summary>The VDI behind a VM's first real disk (a CD drive is a VBD too).</summary>
    private static string FirstDisk(Session session, string vmRef)
    {
        foreach (var vbdRef in VM.get_VBDs(session, vmRef))
            if (VBD.get_type(session, vbdRef.opaque_ref) == vbd_type.Disk)
                return VBD.get_VDI(session, vbdRef.opaque_ref).opaque_ref;
        throw new Exception("no disk found");
    }
}
