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

        // Save the original mode and config so the example restores the host to how it found it, not
        // to a blank "no power-on configured" state.
        var originalMode = Host.get_power_on_mode(session, hostRef);
        var originalConfig = Host.get_power_on_config(session, hostRef);

        // Mode and config travel together: the config carries the credentials the mode needs.
        // "wake-on-lan" is a real, still-supported mode and needs no credentials; the legacy "iLO"/"DRAC"
        // modes were removed from the real power-on plugin and fail the moment host.power_on is actually
        // called ("{mode} script has been removed").
        Host.set_power_on_mode(session, hostRef, "wake-on-lan", new Dictionary<string, string>());
        Console.WriteLine($"Power-on mode:  {Host.get_power_on_mode(session, hostRef)}");
        var config = Host.get_power_on_config(session, hostRef);
        if (config.Count > 0)
            foreach (var kv in config)
                Console.WriteLine($"  {kv.Key} = {kv.Value}");
        else
            Console.WriteLine("  no credentials needed");

        Host.set_power_on_mode(session, hostRef, originalMode, originalConfig);
        var restored = Host.get_power_on_mode(session, hostRef);
        Console.WriteLine($"Restored power-on mode: {(string.IsNullOrEmpty(restored) ? "(none)" : restored)}");
        Console.WriteLine("OK: host-power-on");
        session.logout();
    }
}
