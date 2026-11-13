using System.Collections.Generic;
using System.Linq;
using XenAPI;
using Console = System.Console; // XenAPI also defines a Console class

namespace XenServerWorkflows;

internal static partial class Workflows
{
    /// <summary>
    /// Set a host's out-of-band power-on mode and credentials, then read them back.
    /// </summary>
    public static void HostPowerOn(string url, string user, string password)
    {
        var session = Connect(url, user, password);
        var hostRef = Host.get_all(session).First();

        // Mode and config travel together: the config carries the credentials the mode needs.
        // "wake-on-lan" is a real, still-supported mode and needs no credentials; the legacy "iLO"/"DRAC"
        // modes were removed from the real power-on plugin and fail the moment host.power_on is actually
        // called ("{mode} script has been removed").
        Host.set_power_on_mode(session, hostRef, "wake-on-lan", new Dictionary<string, string>());
        Console.WriteLine($"Power-on mode:  {Host.get_power_on_mode(session, hostRef)}");
        foreach (var kv in Host.get_power_on_config(session, hostRef))
            Console.WriteLine($"  {kv.Key} = {kv.Value}");

        Host.set_power_on_mode(session, hostRef, "", new Dictionary<string, string>());
        Console.WriteLine("OK: host-power-on");
        session.logout();
    }
}
