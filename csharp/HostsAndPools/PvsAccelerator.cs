using System;
using System.Collections.Generic;
using System.Linq;
using XenAPI;
using Console = System.Console; // XenAPI also defines a Console class

namespace XenServerWorkflows;

internal static partial class Workflows
{
    /// <summary>
    /// Document a pool's Citrix Provisioning (PVS) Accelerator setup: each site's read cache (host, size,
    /// storage), its PVS servers (addresses and streaming port range), and which VMs are accelerated versus
    /// the whole pool.
    /// </summary>
    /// <remarks>
    /// Maps the &lt;workflow&gt; argument to the matching self-contained method above, supplying the concrete
    /// objects each one operates on. In your own code you would call these methods directly (see the "Run
    /// it:" line under each) rather than through this dispatcher.
    /// </remarks>
    public static void PvsAccelerator(string url, string user, string password)
    {
        var session = Connect(url, user, password);
        var sites = PVS_site.get_all_records(session);
        if (sites.Count == 0) Console.WriteLine("No PVS Accelerator sites are configured.");
        foreach (var site in sites.Values)
        {
            Console.WriteLine($"Site: {site.name_label}");
            foreach (var csRef in site.cache_storage)
            {
                var cs = PVS_cache_storage.get_record(session, csRef.opaque_ref);
                var cacheHost = Host.get_record(session, cs.host.opaque_ref);
                var sr = SR.get_record(session, cs.SR.opaque_ref);
                Console.WriteLine($"  cache:  {cacheHost.name_label}  {cs.size / (1024L * 1024 * 1024)} GiB on {sr.name_label}");
            }
            foreach (var serverRef in site.servers)
            {
                var server = PVS_server.get_record(session, serverRef.opaque_ref);
                Console.WriteLine($"  server: {string.Join(", ", server.addresses)}  ports {server.first_port}-{server.last_port}");
            }
            // Which VMs are accelerated: walk each proxy to its VIF to its VM.
            var accelerated = new HashSet<string>();
            foreach (var proxyRef in site.proxies)
            {
                var proxy = PVS_proxy.get_record(session, proxyRef.opaque_ref);
                var vif = VIF.get_record(session, proxy.VIF.opaque_ref);
                accelerated.Add(vif.VM.opaque_ref);
            }
            var guests = VM.get_all_records(session)
                .Where(kv => !kv.Value.is_control_domain && !kv.Value.is_a_template && !kv.Value.is_a_snapshot).ToList();
            var count = guests.Count(kv => accelerated.Contains(kv.Key.opaque_ref));
            Console.WriteLine($"  {count} of {guests.Count} VM(s) accelerated");
        }
        Console.WriteLine("OK: pvs-accelerator");
        session.logout();
    }
}
