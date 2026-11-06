using XenAPI;
using Console = System.Console; // XenAPI also defines a Console class

namespace XenServerWorkflows;

internal static partial class Workflows
{
    /// <summary>
    /// Group VMs into an appliance that starts and stops together in a defined order, start and shut it down
    /// as a unit, then remove it.
    /// </summary>
    /// <example>
    /// <code>
    /// Workflows.ManageVapp("https://xenserver", "root", password, "db-01");
    /// </code>
    /// </example>
    public static void ManageVapp(string url, string user, string password, string vmName)
    {
        var session = Connect(url, user, password);
        var vm = VM.get_by_name_label(session, vmName)[0];

        var vapp = VM_appliance.create(session, new VM_appliance
        {
            name_label = "sdk-example-vapp",
            name_description = "Created by the SDK example",
        });

        // `order` decides the sequence: ascending to start, descending to shut down. That ordering is the
        // reason to use a vApp at all rather than selecting several VMs — the database comes up first and
        // goes down last.
        VM.set_appliance(session, vm, vapp);
        VM.set_order(session, vm, 0);
        VM.set_start_delay(session, vm, 5);

        VM_appliance.start(session, vapp, false);
        Console.WriteLine($"Started:        {VM.get_power_state(session, vm)}");

        // shutdown tries each VM's clean shutdown and falls back to a hard one. clean_shutdown alone fails
        // OPERATION_PARTIALLY_FAILED if any member can't shut down cleanly (no guest OS or PV drivers).
        VM_appliance.shutdown(session, vapp);
        Console.WriteLine($"Shut down:      {VM.get_power_state(session, vm)}");

        VM.set_appliance(session, vm, Helper.NullOpaqueRef); // the null reference, spelled out: null would send ""
        VM_appliance.destroy(session, vapp);
        Console.WriteLine("OK: manage-vapp");
        session.logout();
    }
}
