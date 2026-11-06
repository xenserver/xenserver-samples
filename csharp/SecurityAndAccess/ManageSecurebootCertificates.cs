using System.Linq;
using XenAPI;
using Console = System.Console; // XenAPI also defines a Console class

namespace XenServerWorkflows;

internal static partial class Workflows
{
    /// <summary>
    /// Check whether the pool can supply UEFI Secure Boot certificates and whether a guest is ready to use
    /// them, then flag a guest whose certificates have gone stale for a refresh at its next boot — and unflag
    /// it again.
    /// </summary>
    /// <remarks>
    /// Caution: updating a guest's certificates changes its TPM PCR7 measurements, which can trigger
    /// BitLocker recovery on a Windows guest at its next boot. Keep BitLocker recovery keys to hand,
    /// suspend BitLocker on affected VMs first, and do the refresh in a monitored maintenance window.
    /// </remarks>
    /// <example>
    /// <code>
    /// Workflows.ManageSecurebootCertificates("https://xenserver", "root", password);
    /// </code>
    /// </example>
    public static void ManageSecurebootCertificates(string url, string user, string password)
    {
        var session = Connect(url, user, password);
        var pool = Pool.get_all(session).First();

        // A Secure Boot guest carries its own copy of the pool's UEFI certificates, taken when it was
        // created. Rotating the pool's leaves the guest's stale, and the fix is applied at the guest's
        // next boot rather than underneath a running VM — so you flag it and reboot when convenient.
        //
        // First, whether the pool holds the certificates to hand out at all. "ready_no_dbx" means it has
        // the essentials but no revocation list — usable, and not the same answer as "ready".
        Console.WriteLine($"Pool Secure Boot readiness: {Pool.get_guest_secureboot_readiness(session, pool)}");
        Console.WriteLine("  pool holds certificates:  "
                          + !string.IsNullOrEmpty(Pool.get_uefi_certificates(session, pool)));

        // A guest whose certificates have gone stale. Its state is what a client gates the flag/unflag
        // actions on, so it is the field to watch. This is a deliberately-provisioned state, not one a
        // normally-provisioned Secure Boot guest is ever in - so report and stop cleanly rather than
        // letting a bare "no such element" lookup error propagate when nothing needs it right now.
        var candidate = VM.get_all_records(session).FirstOrDefault(kv =>
            !kv.Value.is_a_template && !kv.Value.is_control_domain && !kv.Value.is_a_snapshot
            && kv.Value.secureboot_certificates_state == vm_secureboot_certificates_state.update_available);
        if (candidate.Key == null)
        {
            Console.WriteLine("No guest needs a Secure Boot certificate refresh right now.");
            Console.WriteLine("OK: manage-secureboot-certificates");
            session.logout();
            return;
        }
        var vm = candidate.Key;
        Console.WriteLine($"{VM.get_name_label(session, vm)}: readiness "
                          + $"{VM.get_secureboot_readiness(session, vm)}, certificates "
                          + $"{VM.get_secureboot_certificates_state(session, vm)}");

        // Flagging and unflagging are the same call with opposite booleans.
        VM.update_secureboot_certificates_on_boot(session, vm, true);
        Console.WriteLine($"  flagged for refresh:      {VM.get_secureboot_certificates_state(session, vm)}");

        VM.update_secureboot_certificates_on_boot(session, vm, false);
        Console.WriteLine($"  unflagged:                {VM.get_secureboot_certificates_state(session, vm)}");

        Console.WriteLine("OK: manage-secureboot-certificates");
        session.logout();
    }
}
