using System;
using System.Security.Cryptography;
using XenAPI;
using Console = System.Console; // XenAPI also defines a Console class

namespace XenServerWorkflows;

internal static partial class Workflows
{
    /// <summary>
    /// Change the local superuser password, then change it back.
    /// </summary>
    /// <example>
    /// <code>
    /// Workflows.ChangeRootPassword("https://xenserver", "root", password);
    /// </code>
    /// </example>
    public static void ChangeRootPassword(string url, string user, string password)
    {
        var session = Connect(url, user, password);
        var temporary = Convert.ToBase64String(RandomNumberGenerator.GetBytes(18))
            .Replace('+', '-').Replace('/', '_').TrimEnd('=');

        // session.change_password takes the OLD password as well as the new one, even though you are
        // already authenticated.
        Session.change_password(session, password, temporary);
        Console.WriteLine("Password changed.");
        try
        {
            // The existing session stays valid afterwards — only NEW connections need the new password, so a
            // script can carry on without reconnecting.
            Console.WriteLine($"Session still usable: {Pool.get_all(session).Count == 1}");

            // session.change_password on a ROOT session ignores the old password entirely: the
            // call succeeds regardless of what old_pwd is, so there is no wrong-old-password failure to
            // demonstrate here. The real gate is who may call this at all.
            Console.WriteLine($"Is local superuser (may call change_password): {session.IsLocalSuperuser}");
        }
        finally
        {
            // Put the original password back however the above went, so a failure part-way through
            // doesn't leave root on the temporary one.
            Session.change_password(session, temporary, password);
        }
        Console.WriteLine("Password restored.");
        Console.WriteLine("OK: change-root-password");
        session.logout();
    }
}
