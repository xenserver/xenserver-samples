using System.Collections.Generic;
using XenAPI;
using Console = System.Console; // XenAPI also defines a Console class

namespace XenServerWorkflows;

internal static partial class Workflows
{
    /// <summary>
    /// Connect an ISO-library storage repository to a file share of ISO images (here an NFS export), so the
    /// images are available as installation media.
    /// </summary>
    /// <example>
    /// <code>
    /// Workflows.CreateIsoSr("https://xenserver", "root", password, "192.0.2.10:/isos");
    /// </code>
    /// </example>
    /// <remarks>
    /// Connect an ISO-library SR to a file share of ISO images (here an NFS export, location "server:/path").
    /// </remarks>
    public static void CreateIsoSr(string url, string user, string password, string location)
    {
        var session = Connect(url, user, password);
        var host = Host.get_all(session)[0];
        var dc = new Dictionary<string, string> { ["location"] = location, ["type"] = "nfs_iso" };
        var sr = SR.create(session, host, dc, 0, "sdk-example-iso", "ISO library created by the SDK example",
            "iso", "iso", true, new Dictionary<string, string>());
        Console.WriteLine($"Created ISO SR: {SR.get_uuid(session, sr)}");
        DetachAndForgetSr(session, sr);
        Console.WriteLine("OK: create-iso-sr");
        session.logout();
    }
}
