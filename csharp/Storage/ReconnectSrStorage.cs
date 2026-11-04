using System.Collections.Generic;
using System.Linq;
using XenAPI;
using Console = System.Console; // XenAPI also defines a Console class

namespace XenServerWorkflows;

internal static partial class Workflows
{
    /// <summary>
    /// When the storage behind an SR moves to a new address, point the SR at it: a host's connection to an
    /// SR cannot be edited, so unplug each one, recreate it with the new settings and plug it back.
    /// </summary>
    /// <example>
    /// <code>
    /// Workflows.ReconnectSrStorage("https://xenserver", "root", password, "192.0.2.10", "/export/spare",
    ///     "192.0.2.11");
    /// </code>
    /// </example>
    /// <remarks>
    /// Each host reaches an SR through a PBD, whose device_config (server, path, target, ...) says where the
    /// storage is. A PBD's device_config is fixed when it is created, so changing it means unplugging the
    /// PBD, destroying it, and creating and plugging a new one with the updated settings, host by host. The
    /// SR and its disks are untouched throughout. Every PBD has to be unplugged first, which needs every VM
    /// using the SR to be shut down. This example creates an NFS SR on nfsServer:nfsPath to work on, and
    /// forgets it again at the end; newNfsServer defaults to nfsServer, which reconnects the SR to the same
    /// storage.
    /// </remarks>
    public static void ReconnectSrStorage(string url, string user, string password, string nfsServer,
        string nfsPath, string newNfsServer = null)
    {
        var session = Connect(url, user, password);
        newNfsServer ??= nfsServer;

        var host = Host.get_all(session).First().opaque_ref;
        var sr = SR.create(session, host, new Dictionary<string, string>
        {
            ["server"] = nfsServer,
            ["serverpath"] = nfsPath,
            ["nfsversion"] = "3",
        }, 0, "sdk-example-moved-storage", "SR used by the SDK reconnect example",
            "nfs", "user", true, new Dictionary<string, string>()).opaque_ref;
        try
        {
            var pbds = SR.get_PBDs(session, sr).Select(p => p.opaque_ref).ToList();
            foreach (var pbd in pbds) PBD.unplug(session, pbd);

            foreach (var pbd in pbds)
            {
                var record = PBD.get_record(session, pbd);
                var deviceConfig = new Dictionary<string, string>(record.device_config) { ["server"] = newNfsServer };
                PBD.destroy(session, pbd);
                var replacement = PBD.create(session, new PBD
                {
                    host = record.host,
                    SR = new XenRef<SR>(sr),
                    device_config = deviceConfig,
                    other_config = new Dictionary<string, string>(),
                }).opaque_ref;
                PBD.plug(session, replacement);
                Console.WriteLine($"{Host.get_name_label(session, record.host.opaque_ref)}: now reaches "
                                  + $"{deviceConfig["server"]}:{deviceConfig["serverpath"]}");
            }
        }
        finally
        {
            // Tidy up: detach the SR from every host and forget it, leaving the storage itself untouched.
            DetachAndForgetSr(session, sr);
        }
        Console.WriteLine("OK: reconnect-sr-storage");
        session.logout();
    }
}
