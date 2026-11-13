using System.Collections.Generic;
using System.Linq;
using XenAPI;
using Console = System.Console; // XenAPI also defines a Console class

namespace XenServerWorkflows;

internal static partial class Workflows
{
    /// <summary>
    /// Create a shared NFS storage repository on an NFS export (nfs_server, nfs_path), then detach and forget
    /// it.
    /// </summary>
    /// <example>
    /// <code>
    /// Workflows.CreateNfsSr("https://xenserver", "root", password, "192.0.2.10", "/export/sdk");
    /// </code>
    /// </example>
    public static void CreateNfsSr(string url, string user, string password,
        string nfsServer, string nfsPath, string srName = "sdk-example-nfs")
    {
        var session = Connect(url, user, password);
        var hostRef = Host.get_all_records(session).Keys.First();
        var deviceConfig = new Dictionary<string, string>
        {
            ["server"] = nfsServer,
            ["serverpath"] = nfsPath,
            ["nfsversion"] = "3",
        };

        var srRef = SR.create(session, hostRef, deviceConfig, 0,
            srName, "NFS SR created by the SDK example",
            "nfs", "user", true, new Dictionary<string, string>());
        Console.WriteLine($"Created SR: {SR.get_uuid(session, srRef)}");

        DetachAndForgetSr(session, srRef);
        Console.WriteLine("OK: create-nfs-sr");
        session.logout();
    }
}
