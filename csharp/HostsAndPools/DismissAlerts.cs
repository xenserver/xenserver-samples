using System.Linq;
using XenAPI;
using Console = System.Console; // XenAPI also defines a Console class

namespace XenServerWorkflows;

internal static partial class Workflows
{
    /// <summary>
    /// List the pool's alerts, then dismiss one — what the Notifications view does.
    /// </summary>
    public static void DismissAlerts(string url, string user, string password)
    {
        var session = Connect(url, user, password);
        var messages = Message.get_all_records(session);
        Console.WriteLine($"Alerts:         {messages.Count}");

        var first = messages.FirstOrDefault();
        if (first.Key == null)
        {
            Console.WriteLine("No alerts to dismiss.");
        }
        else
        {
            Console.WriteLine($"Dismissing:     {first.Value.name} (priority {first.Value.priority})");
            // Dismiss in XenCenter's Notifications view is exactly this call.
            Message.destroy(session, first.Key);
            Console.WriteLine($"Alerts left:    {Message.get_all_records(session).Count}");
        }
        Console.WriteLine("OK: dismiss-alerts");
        session.logout();
    }
}
