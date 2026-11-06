using System.Collections.Generic;
using XenAPI;
using Console = System.Console; // XenAPI also defines a Console class

namespace XenServerWorkflows;

internal static partial class Workflows
{
    /// <summary>
    /// Attach a virtual network interface to a VM and remove it again.
    /// </summary>
    /// <example>
    /// <code>
    /// Workflows.ManageVif("https://xenserver", "root", password, "Rocky Linux 8");
    /// </code>
    /// </example>
    public static void ManageVif(string url, string user, string password,
        string templateName, string newVmName = "sdk-example-vif")
    {
        var session = Connect(url, user, password);
        var vm = VM.clone(session, TemplateByName(session, templateName), newVmName);
        Provision(session, vm);
        var netRef = Network.get_all(session)[0];
        var device = VM.get_allowed_VIF_devices(session, vm)[0];

        var vif = VIF.create(session, new VIF
        {
            VM = vm,
            network = netRef,
            device = device,
            MAC = "",
            MTU = 1500,
            other_config = new Dictionary<string, string>(),
            qos_algorithm_type = "",
            qos_algorithm_params = new Dictionary<string, string>(),
        });
        Console.WriteLine($"Attached a VIF on device {device}; VM now has {VM.get_VIFs(session, vm).Count} NIC(s)");

        VIF.destroy(session, vif);
        DestroyVmAndDisks(session, vm);
        Console.WriteLine("OK: manage-vif");
        session.logout();
    }
}
