using System.Collections.Generic;
using System.Linq;
using XenAPI;
using Console = System.Console; // XenAPI also defines a Console class

namespace XenServerWorkflows;

internal static partial class Workflows
{
    /// <summary>
    /// Turn on pool High Availability: choose a shared SR as the heartbeat statefile, compute how many host
    /// failures the pool can tolerate, enable HA, then disable it again.
    /// </summary>
    /// <example>
    /// <code>
    /// Workflows.ConfigureHa("https://xenserver", "root", password, "Shared NFS");
    /// </code>
    /// </example>
    public static void ConfigureHa(string url, string user, string password, string heartbeatSrName)
    {
        var session = Connect(url, user, password);
        var poolRef = Pool.get_all_records(session).Keys.First().opaque_ref;

        // The HA heartbeat statefile needs a shared SR; confirm the chosen one can host it.
        var srRef = SrByName(session, heartbeatSrName, shared: true);
        Console.WriteLine($"Heartbeat SR:  {SR.get_name_label(session, srRef)}");
        SR.assert_can_host_ha_statefile(session, srRef);

        // What HA does per VM. The restart priority decides which guests come back first after a host
        // failure, and whether a VM is protected at all; "restart" is protected, an empty string is not.
        var guest = VM.get_all_records(session).First(kv =>
            !kv.Value.is_a_template && !kv.Value.is_control_domain && !kv.Value.is_a_snapshot).Key.opaque_ref;

        // How many host failures can the pool tolerate WITH the VMs you mean to protect? Plan for those
        // (as XenCenter's HA wizard does): a target computed with none protected can be too high, and
        // protecting a VM afterwards then fails HA_OPERATION_WOULD_BREAK_FAILOVER_PLAN.
        var ntol = Pool.ha_compute_hypothetical_max_host_failures_to_tolerate(
            session, new Dictionary<XenRef<VM>, string> { { new XenRef<VM>(guest), "restart" } });
        Console.WriteLine($"Max failures:  {ntol}");
        Pool.set_ha_host_failures_to_tolerate(session, poolRef, ntol);
        Pool.enable_ha(session, new List<XenRef<SR>> { new(srRef) }, new Dictionary<string, string>());
        try
        {
            Console.WriteLine($"HA enabled:    {Pool.get_ha_enabled(session, poolRef)}");

            var wasPriority = VM.get_ha_restart_priority(session, guest);
            VM.set_ha_restart_priority(session, guest, "restart");
            Console.WriteLine($"{VM.get_name_label(session, guest)} priority: '{wasPriority}' -> " +
                $"'{VM.get_ha_restart_priority(session, guest)}'");
            VM.set_ha_restart_priority(session, guest, wasPriority);

            // And a pool-wide judgement call: if a guest shuts itself down from the inside, is that a
            // failure HA should undo, or an administrator's intent it should respect?
            var restartOnInternalShutdown = Pool.get_ha_reboot_vm_on_internal_shutdown(session, poolRef);
            Console.WriteLine($"Restart on internal shutdown: {restartOnInternalShutdown}");
        }
        finally
        {
            // Turn HA back off however the above went: left on, it blocks host reboots, coordinator
            // changes and more (HA_IS_ENABLED, HA_OPERATION_WOULD_BREAK_FAILOVER_PLAN).
            Pool.disable_ha(session);
        }
        Console.WriteLine($"HA enabled:    {Pool.get_ha_enabled(session, poolRef)}");
        Console.WriteLine("OK: configure-ha");
        session.logout();
    }
}
