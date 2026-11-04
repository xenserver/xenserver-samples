using System;
using System.Linq;
using XenAPI;
using Console = System.Console; // XenAPI also defines a Console class

namespace XenServerWorkflows;

internal static partial class Workflows
{
    /// <summary>
    /// Take a host down and bring it back: stop it accepting new VMs, move the ones it is running elsewhere,
    /// reboot it, then power it right off and back on again.
    /// </summary>
    public static void RestartHost(string url, string user, string password)
    {
        var session = Connect(url, user, password);
        var pool = Pool.get_all(session).First().opaque_ref;

        // Rebooting a host is never just the reboot: anything running on it has to go somewhere first,
        // and the host has to stop accepting new VMs while that happens.
        //
        // Not the coordinator: it is the host this session is talking to, and taking it down would drop
        // the connection underneath the rest of the example.
        var coordinator = Pool.get_master(session, pool).opaque_ref;
        var host = Host.get_all(session).First(h => h.opaque_ref != coordinator).opaque_ref;
        Console.WriteLine($"Restarting {Host.get_name_label(session, host)}");
        Console.WriteLine($"  enabled={Host.get_enabled(session, host)}, guests={GuestCount(session, host)}");

        // Disabled means "accept no new VMs"; it does not move anything on its own.
        Host.disable(session, host);
        Console.WriteLine($"  disabled:   enabled={Host.get_enabled(session, host)}");

        // Evacuate moves the guests elsewhere in the pool. Afterwards only the control domain — the
        // host's own management VM, which cannot move — is left.
        Host.evacuate(session, host);
        Console.WriteLine($"  evacuated:  guests={GuestCount(session, host)}");

        Host.reboot(session, host);
        // A real reboot takes minutes. Wait for the host to drop out and come back (live in its
        // host_metrics), then enable it. A host disabled the default way (auto_enable=true) re-enables
        // itself once its toolstack is up again, but only then - and one disabled with auto_enable=false
        // never does - so enable it explicitly rather than depend on either.
        WaitForHostLive(session, host, false, 600);
        WaitForHostLive(session, host, true, 1200, 10);
        EnableWhenBooted(session, host);
        Console.WriteLine($"  rebooted, re-enabled: enabled={Host.get_enabled(session, host)}");

        // The other ending: off, and back on out of band - but only demonstrated if that is actually
        // configured: a real host.power_on has no retry of its own and simply fails,
        // "The host failed to power on.", if no mechanism is configured or working.
        if (!string.IsNullOrEmpty(Host.get_power_on_mode(session, host)))
        {
            Host.disable(session, host);
            Host.shutdown(session, host);
            WaitForHostLive(session, host, false);
            Console.WriteLine($"  shut down:  live={HostLive(session, host)}");
            Host.power_on(session, host);
            WaitForHostLive(session, host, true, 1200, 10);
            Console.WriteLine($"  powered on: live={HostLive(session, host)}");
            EnableWhenBooted(session, host);
            Console.WriteLine($"  re-enabled: enabled={Host.get_enabled(session, host)}");
        }
        else
        {
            Console.WriteLine("  skipping shutdown/power-on: no out-of-band power-on mode is configured on this host");
        }

        Console.WriteLine("OK: restart-host");
        session.logout();
    }

    /// <summary>
    /// Poll host_metrics.live until it matches, rather than issuing the next power command immediately -
    /// real out-of-band power control has no retry of its own, so a tool that doesn't wait can issue a
    /// second command while the first is still in flight.
    /// </summary>
    private static void WaitForHostLive(Session session, string host, bool want,
        int timeoutSeconds = 60, int intervalSeconds = 2)
    {
        var deadline = DateTime.UtcNow.AddSeconds(timeoutSeconds);
        while (HostLive(session, host) != want)
        {
            if (DateTime.UtcNow > deadline) throw new Exception($"host did not reach live={want} in time");
            System.Threading.Thread.Sleep(intervalSeconds * 1000);
        }
    }

    /// <summary>Resident VMs excluding the control domain, which never moves.</summary>
    private static int GuestCount(Session session, string host) =>
        Host.get_resident_VMs(session, host).Count(v => !VM.get_is_control_domain(session, v.opaque_ref));
}
