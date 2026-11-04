using System.Linq;
using XenAPI;
using Console = System.Console; // XenAPI also defines a Console class

namespace XenServerWorkflows;

internal static partial class Workflows
{
    /// <summary>
    /// Attach a virtual TPM to a halted VM, read it back and remove it again. A VM may have at most one, and
    /// only while it is halted.
    /// </summary>
    /// <example>
    /// <code>
    /// Workflows.ManageVtpm("https://xenserver", "root", password);
    /// </code>
    /// </example>
    public static void ManageVtpm(string url, string user, string password)
    {
        var session = Connect(url, user, password);

        var vm = VM.get_all_records(session).First(kv =>
            !kv.Value.is_a_template && !kv.Value.is_control_domain && !kv.Value.is_a_snapshot &&
            kv.Value.power_state == vm_power_state.Halted && kv.Value.VTPMs.Count == 0);
        Console.WriteLine($"Attaching a vTPM to {vm.Value.name_label}");

        // is_unique=false: the vTPM may be copied along with the VM. A VM may have at most one, and it
        // can only be attached while Halted — the device is presented at boot.
        var vtpm = VTPM.create(session, vm.Key.opaque_ref, false);
        var record = VTPM.get_record(session, vtpm.opaque_ref);
        Console.WriteLine($"  persistence backend: {record.persistence_backend}");
        Console.WriteLine($"  unique to this VM:   {record.is_unique}");
        Console.WriteLine($"  VM now has {VM.get_VTPMs(session, vm.Key.opaque_ref).Count} vTPM(s)");

        // The VM advertises whether another can be added; once it has one, it cannot.
        Console.WriteLine("  can add another:     " +
            VM.get_allowed_operations(session, vm.Key.opaque_ref).Contains(vm_operations.create_vtpm));

        VTPM.destroy(session, vtpm.opaque_ref);
        Console.WriteLine($"  after removal:       {VM.get_VTPMs(session, vm.Key.opaque_ref).Count} vTPM(s)");
        Console.WriteLine("OK: manage-vtpm");
        session.logout();
    }
}
