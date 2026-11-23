using System.Collections.Generic;
using XenAPI;
using Console = System.Console; // XenAPI also defines a Console class

namespace XenServerWorkflows;

internal static partial class Workflows
{
    /// <summary>
    /// Create an internal network — an isolated virtual switch with no physical NIC — for VMs to talk to each
    /// other privately.
    /// </summary>
    /// <example>
    /// <code>
    /// Workflows.CreateNetwork("https://xenserver", "root", password, "sdk-example-net");
    /// </code>
    /// </example>
    public static void CreateNetwork(string url, string user, string password,
        string networkName = "sdk-example-net")
    {
        var session = Connect(url, user, password);
        var record = new Network
        {
            name_label = networkName,
            name_description = "Internal network created by the SDK example",
            MTU = 1500,
            other_config = new Dictionary<string, string>(),
        };
        var netRef = Network.create(session, record);
        Console.WriteLine($"Created network: {Network.get_uuid(session, netRef)}");

        // Raise the MTU to use jumbo frames. Every NIC and switch along the path has to agree, so this is
        // a property of the network rather than of any one interface on it.
        Network.set_MTU(session, netRef, 9000);
        Console.WriteLine($"MTU now:         {Network.get_MTU(session, netRef)}");

        Network.destroy(session, netRef);
        Console.WriteLine("OK: create-network");
        session.logout();
    }
}
