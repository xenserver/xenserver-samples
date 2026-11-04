using System;
using System.Linq;
using XenAPI;
using Console = System.Console; // XenAPI also defines a Console class

namespace XenServerWorkflows;

internal static partial class Workflows
{
    /// <summary>
    /// Replicate the pool's database to shared storage, read it back as a separate database to see what it
    /// describes, and recover a VM out of it into a second, standby pool (dr_url).
    /// </summary>
    /// <example>
    /// <code>
    /// Workflows.DisasterRecovery("https://xenserver", "root", password, "https://standby-pool");
    /// </code>
    /// </example>
    /// <remarks>
    /// Replicate the pool's database to shared storage, then recover a VM out of it onto a second, standby
    /// pool. That destination has to be a DIFFERENT, standby pool: recovering a VM back into the exact pool
    /// it was replicated from can't actually succeed with force=false (VM_TO_IMPORT_IS_NOT_NEWER_VERSION),
    /// and passing force=true instead would succeed by REPLACING the live original - exactly the opposite of
    /// what a DR demo should show, and the thing that would actually destroy a live VM if ever pointed at the
    /// same pool it replicated from. Track the recovered VM by uuid, never by name: a name can coincidentally
    /// collide with something already on the destination pool.
    /// </remarks>
    public static void DisasterRecovery(string url, string user, string password, string drUrl)
    {
        if (string.IsNullOrEmpty(drUrl))
            throw new Exception("disaster-recovery needs a second pool to recover into: pass " +
                                "dr_url=<url of a standby pool>");

        var session = Connect(url, user, password);
        var drSession = Connect(drUrl, user, password);

        // Replication needs shared storage the standby pool can attach too, and only block storage (iSCSI,
        // HBA) supports it - an NFS SR fails SR_OPERATION_NOT_SUPPORTED. The server checks rather than
        // taking your word for it, so ask each candidate, as XenCenter's DR wizard does.
        static bool Succeeds(Action call)
        {
            try { call(); return true; }
            catch (Failure) { return false; }
        }
        var sr = SR.get_all_records(session).FirstOrDefault(kv =>
            kv.Value.shared && kv.Value.content_type != "iso"
            && Succeeds(() => SR.assert_supports_database_replication(session, kv.Key.opaque_ref))).Key?.opaque_ref
            ?? throw new Exception("no shared SR here supports database replication (it needs iSCSI or HBA storage)");
        Console.WriteLine($"Replicating pool metadata to {SR.get_name_label(session, sr)}");
        SR.enable_database_replication(session, sr);

        // Everything from here happens on the STANDBY pool, the way XenCenter's DR wizard works from the
        // pool you fail over to: it has the same SR attached, rescans it to see the metadata disk just
        // written, opens the database there, and recovers into itself - VM.recover's session_to has to be
        // a session of the server running the call (HANDLE_INVALID otherwise).
        string drSr;
        try { drSr = SR.get_by_uuid(drSession, SR.get_uuid(session, sr)).opaque_ref; }
        catch (Failure)
        {
            throw new Exception($"the standby pool has not attached {SR.get_name_label(session, sr)}: " +
                                "attach the same storage there first");
        }
        SR.scan(drSession, drSr);
        var vdi = SR.get_VDIs(drSession, drSr)
            .First(v => VDI.get_type(drSession, v.opaque_ref) == vdi_type.metadata).opaque_ref;
        Console.WriteLine($"  metadata disk: {VDI.get_uuid(drSession, vdi)}");

        // A session onto the replicated database rather than the live pool. Assembled from the URL and the
        // session id we were handed rather than with Session(url, opaqueRef): that constructor queries the
        // pool immediately to work out the API version, which happens before there is any chance to accept
        // the host's self-signed certificate.
        var metadata = new Session(drUrl) { opaque_ref = VDI.open_database(drSession, vdi).opaque_ref };
        metadata.JsonRpcClient.ServerCertificateValidationCallback = (req, cert, chain, errors) => true;

        // Only real guest VMs are recoverable - exclude templates, control domains and snapshots.
        var recoverable = VM.get_all_records(metadata).Where(kv =>
            !kv.Value.is_a_template && !kv.Value.is_control_domain && !kv.Value.is_a_snapshot).ToList();
        Console.WriteLine($"  the replicated database describes {recoverable.Count} recoverable VM(s)");

        // Only a VM whose disks are all on storage the standby pool can see can be recovered there - the
        // check runs on the METADATA session, and session_to says where the VM should land: the STANDBY
        // pool's session, not this one. Take the first (by name) that passes, as the DR wizard lists them.
        var candidates = recoverable.OrderBy(kv => kv.Value.name_label)
            .Where(kv => Succeeds(() => VM.assert_can_be_recovered(metadata, kv.Key.opaque_ref, drSession.opaque_ref)))
            .ToList();
        if (candidates.Count == 0)
            throw new Exception("no VM in the replicated database has all its disks on storage the standby pool can see");
        var target = candidates[0];
        var targetUuid = target.Value.uuid;
        var name = target.Value.name_label;
        Console.WriteLine($"  recovering {name}");
        VM.recover(metadata, target.Key.opaque_ref, drSession.opaque_ref, false);

        // It is a real VM on the standby pool now, not merely a call that returned - look it up by the
        // uuid full_restore preserved, not by name. NO fallback to the source pool: a second pool is the
        // only correct target, and on a real pool this lookup always succeeds.
        var recovered = VM.get_by_uuid(drSession, targetUuid).opaque_ref;
        Console.WriteLine($"  {name} is {VM.get_power_state(drSession, recovered)} on the standby pool");

        // Tidy up on the standby pool only, by uuid - never touch the source pool's VMs, and never
        // guess by name. Destroy the VM record but NOT its disks: they are the protected pool's own
        // disks on the shared SR, not copies.
        VM.destroy(drSession, recovered);
        SR.disable_database_replication(session, sr);
        Console.WriteLine("OK: disaster-recovery");
        session.logout();
        drSession.logout();
    }
}
