using System.Collections.Generic;
using XenAPI;
using Console = System.Console; // XenAPI also defines a Console class

namespace XenServerWorkflows;

internal static partial class Workflows
{
    /// <summary>
    /// Connect a shared storage repository to an SMB/CIFS file share, passing the server, share path and
    /// credentials (the password as a secret, never in plain text).
    /// </summary>
    /// <example>
    /// <code>
    /// Workflows.CreateSmbSr("https://xenserver", "root", password, "192.0.2.40", "/vmstore", "Administrator", "Password1");
    /// </code>
    /// </example>
    /// <remarks>
    /// Connect a shared SR to an SMB/CIFS file share (create validates + sizes from the share). The password
    /// travels as a Secret, not plaintext device-config.
    /// </remarks>
    public static void CreateSmbSr(string url, string user, string password, string server, string share,
        string smbUsername, string smbPassword, string srName = "sdk-example-smb")
    {
        const long GiB = 1024L * 1024 * 1024;
        var session = Connect(url, user, password);
        var host = Host.get_all(session)[0].opaque_ref;

        var secret = Secret.create(session, new Secret
        {
            value = smbPassword,
            other_config = new Dictionary<string, string>(),
        }).opaque_ref;
        var dc = new Dictionary<string, string>
        {
            // server is the share as one UNC path, //server/share: the SMB driver has no separate serverpath.
            ["server"] = $"//{server}{share}",
            ["username"] = smbUsername,
            ["password_secret"] = Secret.get_uuid(session, secret),
        };
        var sr = SR.create(session, host, dc, 0, srName, "SMB SR created by the SDK example",
            "smb", "user", true, new Dictionary<string, string>());
        Console.WriteLine($"Created SR: {SR.get_uuid(session, sr)} ({SR.get_physical_size(session, sr) / GiB} GiB)");
        DetachAndForgetSr(session, sr);
        Secret.destroy(session, secret);
        Console.WriteLine("OK: create-smb-sr");
        session.logout();
    }
}
