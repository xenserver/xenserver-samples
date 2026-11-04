using System.Linq;
using XenAPI;
using Console = System.Console; // XenAPI also defines a Console class

namespace XenServerWorkflows;

internal static partial class Workflows
{
    /// <summary>
    /// Enumerate the pool's VM templates, both built-in and custom.
    /// </summary>
    /// <example>
    /// <code>
    /// Workflows.ListTemplates("https://xenserver", "root", password);
    /// </code>
    /// </example>
    public static void ListTemplates(string url, string user, string password)
    {
        var session = Connect(url, user, password);
        var templates = VM.get_all_records(session).Values
            .Where(v => v.is_a_template).OrderBy(v => v.name_label).ToList();
        Console.WriteLine($"Templates ({templates.Count}):");
        foreach (var t in templates.Take(8))
        {
            var isDefault = t.other_config.ContainsKey("default_template");
            Console.WriteLine($"  - {t.name_label}{(isDefault ? " [built-in]" : "")}");
        }
        Console.WriteLine("OK: list-templates");
        session.logout();
    }
}
