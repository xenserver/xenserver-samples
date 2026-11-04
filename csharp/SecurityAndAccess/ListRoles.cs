using System.Linq;
using XenAPI;
using Console = System.Console; // XenAPI also defines a Console class

namespace XenServerWorkflows;

internal static partial class Workflows
{
    /// <summary>
    /// Enumerate the pool's role-based access control (RBAC) roles — the roles that can be granted to users.
    /// </summary>
    /// <example>
    /// <code>
    /// Workflows.ListRoles("https://xenserver", "root", password);
    /// </code>
    /// </example>
    public static void ListRoles(string url, string user, string password)
    {
        var session = Connect(url, user, password);
        // Role is the one class XenCenter still bulk-downloads; RBAC subjects map to these roles. Role records
        // include every permission too; the roles a user can be granted are the ones made of permissions
        // (non-empty subroles), as xe role-list shows.
        var roles = Role.get_all_records(session).Values.Where(r => r.subroles.Count > 0)
            .Select(r => r.name_label).Distinct().OrderBy(n => n).ToList();
        Console.WriteLine($"Roles ({roles.Count}): {string.Join(", ", roles.Take(8))}");
        Console.WriteLine("OK: list-roles");
        session.logout();
    }
}
