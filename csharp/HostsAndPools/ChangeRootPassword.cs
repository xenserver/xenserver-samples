using XenAPI;
using Console = System.Console; // XenAPI also defines a Console class

namespace XenServerWorkflows;

internal static partial class Workflows
{
    /// <summary>
    /// Change the local superuser password, handle the wrong-old-password failure, and change it back.
    /// </summary>
    /// <example>
    /// <code>
    /// Workflows.ChangeRootPassword("https://xenserver", "root", password);
    /// </code>
    /// </example>
    public static void ChangeRootPassword(string url, string user, string password)
    {
        var session = Connect(url, user, password);
        const string temporary = "sdk-example-temp-password";

        // session.change_password takes the OLD password as well as the new one, even though you are
        // already authenticated.
        Session.change_password(session, password, temporary);
        Console.WriteLine("Password changed.");

        // The existing session stays valid afterwards — only NEW connections need the new password, so a
        // script can carry on without reconnecting.
        Console.WriteLine($"Session still usable: {Pool.get_all(session).Count == 1}");

        // session.change_password on a ROOT session ignores the old password entirely (CA-13567): the
        // call succeeds regardless of what old_pwd is, so "supplying the wrong old password" is not a
        // real failure to demonstrate here. The real gate is who may call this at all.
        Console.WriteLine($"Is local superuser (may call change_password): {session.IsLocalSuperuser}");

        Session.change_password(session, temporary, password);
        Console.WriteLine("Password restored.");
        Console.WriteLine("OK: change-root-password");
        session.logout();
    }
}
