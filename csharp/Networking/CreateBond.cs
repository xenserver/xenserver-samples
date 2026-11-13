using System;
using System.Collections.Generic;
using System.Linq;
using XenAPI;
using Console = System.Console; // XenAPI also defines a Console class

namespace XenServerWorkflows;

internal static partial class Workflows
{
    /// <summary>
    /// Bond two spare network interfaces onto a new network for redundancy and throughput, read the bond
    /// back, then dissolve it.
    /// </summary>
    /// <example>
    /// <code>
    /// Workflows.CreateBond("https://xenserver", "root", password);
    /// </code>
    /// </example>
    public static void CreateBond(string url, string user, string password)
    {
        var session = Connect(url, user, password);
        var host = Host.get_all(session)[0];

        // Pick up any NIC racked since the host booted. Cheap, and without it a card added a moment ago
        // is not there to bond.
        PIF.scan(session, host);

        // Spare NICs only. A bond that includes the management interface moves the management address
        // onto the bond master — on a real host that is how you lose the connection you are working over.
        var spares = PIF.get_all_records(session)
            .Where(p => p.Value.host.Equals(host) && !p.Value.management && p.Value.physical)
            .Take(2).Select(p => p.Key).ToList();
        if (spares.Count < 2)
            throw new Exception($"{Host.get_name_label(session, host)} has {spares.Count} spare NIC(s); " +
                                 "a bond needs two that aren't the management interface");
        Console.WriteLine($"Bonding:      " +
                          $"{string.Join(", ", spares.Select(p => PIF.get_device(session, p)))}");

        // The bond needs a network to sit on.
        var network = Network.create(session, new Network
        {
            name_label = "sdk-example-bond",
            name_description = "Created by the SDK example",
            other_config = new Dictionary<string, string>(),
        });

        var bond = Bond.create(session, network, spares, "", bond_mode.balance_slb);
        var master = Bond.get_master(session, bond);
        Console.WriteLine($"Bond master:  {PIF.get_device(session, master)}");
        Console.WriteLine($"Mode:         {Bond.get_mode(session, bond)}");

        // Dissolving returns the NICs to standalone use (and moves management back, had it been bonded).
        Bond.destroy(session, bond);
        Network.destroy(session, network);
        Console.WriteLine($"Bonds left:   {Bond.get_all(session).Count}");
        Console.WriteLine("OK: create-bond");
        session.logout();
    }
}
