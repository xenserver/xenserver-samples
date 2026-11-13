using System;
using System.Linq;
using XenAPI;
using Console = System.Console; // XenAPI also defines a Console class

namespace XenServerWorkflows;

internal static partial class Workflows
{
    /// <summary>
    /// Turn on pool metadata replication: the pool writes its database - the configuration of its VMs and
    /// vApps - to a disk on an iSCSI or Fibre Channel SR. Have your storage array replicate that SR, and
    /// the VMs' SRs, to the disaster recovery site; a pool there can then recover the VMs from the
    /// replica (see <see cref="DisasterRecoveryFailover"/>).
    /// </summary>
    /// <example>
    /// <code>
    /// Workflows.ConfigureDisasterRecovery("https://xenserver", "root", password);
    /// </code>
    /// </example>
    /// <remarks>
    /// <para>
    /// Only SRs on a LUN - iSCSI or Fibre Channel/SAS (HBA) - can hold the pool's database, and every host
    /// must have the SR attached. The server says which qualify: SR.assert_supports_database_replication
    /// fails for any that can't (an NFS SR fails SR_OPERATION_NOT_SUPPORTED), so ask each one rather than
    /// guessing from its type. A pool can replicate to up to 8 SRs.
    /// </para>
    /// <para>
    /// Replication is only useful while it is on. So that the example leaves the pool as it found it, it
    /// turns replication off again if it was off to start with; in practice, leave it on.
    /// </para>
    /// </remarks>
    public static void ConfigureDisasterRecovery(string url, string user, string password, string srName = null)
    {
        var session = Connect(url, user, password);

        bool SupportsReplication(XenRef<SR> sr)
        {
            try { SR.assert_supports_database_replication(session, sr); return true; }
            catch (Failure) { return false; }
        }
        var candidates = SR.get_all_records(session)
            .Where(kv => kv.Value.shared && kv.Value.content_type != "iso" && SupportsReplication(kv.Key))
            .Select(kv => kv.Key).ToList();
        var names = string.Join(", ", candidates.Select(sr => SR.get_name_label(session, sr)));
        Console.WriteLine($"SRs that can hold the pool metadata: {(names.Length > 0 ? names : "none")}");
        if (!string.IsNullOrEmpty(srName))
            candidates = candidates.Where(sr => SR.get_name_label(session, sr) == srName).ToList();
        if (candidates.Count == 0)
            throw new Exception($"no SR here can hold the pool metadata{(srName != null ? $" named '{srName}'" : "")}: " +
                                "it needs an iSCSI or Fibre Channel SR attached to every host");
        var chosen = candidates[0];
        var name = SR.get_name_label(session, chosen);

        // The pool's own metadata disk on this SR is what says replication is on: a disk of type metadata
        // whose metadata_of_pool is this pool.
        var pool = Pool.get_all(session)[0];
        XenRef<VDI> MetadataDisk() => SR.get_VDIs(session, chosen).FirstOrDefault(v =>
            VDI.get_type(session, v) == vdi_type.metadata && VDI.get_metadata_of_pool(session, v).Equals(pool));

        var wasOn = MetadataDisk() != null;
        if (wasOn)
            Console.WriteLine($"The pool metadata is already replicated to {name}");
        else
        {
            Console.WriteLine($"Replicating the pool metadata to {name}");
            SR.enable_database_replication(session, chosen);
        }

        var vdi = MetadataDisk();
        Console.WriteLine($"  metadata disk: {VDI.get_name_label(session, vdi)} ({VDI.get_uuid(session, vdi)}), " +
                          $"{VDI.get_virtual_size(session, vdi) / (1024 * 1024)} MiB, " +
                          $"up to date: {VDI.get_metadata_latest(session, vdi)}");

        if (!wasOn)
        {
            // Turning replication off destroys the metadata disk.
            SR.disable_database_replication(session, chosen);
            Console.WriteLine("Turned replication off again, as it was before");
        }
        Console.WriteLine("OK: configure-disaster-recovery");
        session.logout();
    }
}
