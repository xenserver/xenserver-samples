using System;
using System.Linq;
using XenAPI;
using Console = System.Console; // XenAPI also defines a Console class

namespace XenServerWorkflows;

internal static partial class Workflows
{
    /// <summary>
    /// List the pool's member hosts and which one coordinates it, promote a different host to coordinator,
    /// then promote the original back.
    /// </summary>
    /// <example>
    /// <code>
    /// Workflows.ManagePoolMembership("https://xenserver", "root", password);
    /// </code>
    /// </example>
    public static void ManagePoolMembership(string url, string user, string password)
    {
        var session = Connect(url, user, password);
        var poolRef = Pool.get_all(session)[0].opaque_ref;

        var hosts = Host.get_all_records(session);
        var original = Pool.get_master(session, poolRef).opaque_ref;
        Console.WriteLine($"Coordinator: {hosts[new XenRef<Host>(original)].name_label}");
        foreach (var h in hosts)
            Console.WriteLine($"  member: {h.Value.name_label}{(h.Key.opaque_ref == original ? " (coordinator)" : "")}");

        // Promote another member. The pool database moves with the role and clients are redirected, so
        // this briefly interrupts management traffic — it does not move any VM.
        var other = hosts.Keys.First(k => k.opaque_ref != original).opaque_ref;
        Pool.designate_new_master(session, other);
        Console.WriteLine($"Promoting:   {hosts[new XenRef<Host>(other)].name_label} " +
                          "(xapi restarts pool-wide; reconnecting)");

        // designate_new_master runs a two-phase commit across every host and ends by restarting xapi
        // pool-wide - the session this call was made on, and the connection itself, do not survive it.
        // Reconnect (with a bounded wait) before touching the pool again, and re-resolve every ref from
        // the fresh session rather than assuming the old ones are still good.
        session = ReconnectAfterMasterChange(url, user, password, hosts[new XenRef<Host>(other)].uuid);
        poolRef = Pool.get_all(session)[0].opaque_ref;
        Console.WriteLine($"Promoted:    {Host.get_name_label(session, Pool.get_master(session, poolRef).opaque_ref)}");

        // Put it back. Ejecting a member (Pool.eject) is the other half of this surface and is
        // deliberately not shown: it cannot be undone from the pool, because rejoining is initiated by
        // the ejected host.
        Pool.designate_new_master(session, original);
        Console.WriteLine($"Restoring:   {hosts[new XenRef<Host>(original)].name_label} (reconnecting again)");

        session = ReconnectAfterMasterChange(url, user, password, hosts[new XenRef<Host>(original)].uuid);
        poolRef = Pool.get_all(session)[0].opaque_ref;
        Console.WriteLine($"Restored:    {Host.get_name_label(session, Pool.get_master(session, poolRef).opaque_ref)}");

        Console.WriteLine("OK: manage-pool-membership");
        session.logout();
    }

    /// <summary>
    /// Wait out a pool-wide xapi restart (Pool.designate_new_master) and reconnect.
    ///
    /// designate_new_master returns BEFORE the change: for a while the old coordinator still answers,
    /// and still says it is the coordinator, until xapi restarts across the pool. So reconnecting is not
    /// enough - keep reconnecting until the pool names the new coordinator (by uuid; Connect follows
    /// HOST_IS_SLAVE to wherever the coordinator now is). That can take minutes. </summary>
    private static Session ReconnectAfterMasterChange(string url, string user, string password,
        string newMasterUuid, int timeoutSeconds = 600, int intervalSeconds = 5)
    {
        var deadline = DateTime.UtcNow.AddSeconds(timeoutSeconds);
        object lastError = null;
        while (DateTime.UtcNow < deadline)
        {
            try
            {
                var session = Connect(url, user, password);
                var master = Pool.get_master(session, Pool.get_all(session)[0].opaque_ref).opaque_ref;
                // The new coordinator answers before the pool has settled - calls made too soon fail
                // (HANDLE_INVALID on the operation's own task) - so also wait for every host to be back,
                // live and enabled.
                if (Host.get_uuid(session, master) == newMasterUuid && Host.get_all_records(session).Values.All(
                        r => r.enabled && Host_metrics.get_live(session, r.metrics.opaque_ref)))
                    return session;
                session.logout();
                lastError = "the pool has not settled under the new coordinator";
            }
            catch (Exception e)
            {
                lastError = e;
            }
            System.Threading.Thread.Sleep(intervalSeconds * 1000);
        }
        throw new Exception($"the pool did not come back after the master change: {lastError}");
    }
}
