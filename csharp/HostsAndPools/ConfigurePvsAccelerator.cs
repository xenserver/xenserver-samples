using System;
using System.Linq;
using XenAPI;
using Console = System.Console; // XenAPI also defines a Console class

namespace XenServerWorkflows;

internal static partial class Workflows
{
    /// <summary>
    /// Build a PVS Accelerator site from nothing and take it down again: introduce the site and a PVS server,
    /// put a read cache on each host's local storage, accelerate a VM by proxying its first NIC, then forget
    /// the site — which cascades to everything hanging off it.
    /// </summary>
    /// <example>
    /// <code>
    /// Workflows.ConfigurePvsAccelerator("https://xenserver", "root", password, "db-01");
    /// </code>
    /// </example>
    public static void ConfigurePvsAccelerator(string url, string user, string password, string vmName)
    {
        var session = Connect(url, user, password);

        // Check the VM first, before creating anything: it needs a NIC for the proxy to sit on, and one
        // that no site accelerates yet (a VIF takes one proxy: PVS_PROXY_ALREADY_PRESENT). It need not be
        // running - a proxy on a halted VM just reports "stopped" until it starts.
        var vm = VmByName(session, vmName);
        var vifs = VM.get_VIFs(session, vm)
            .OrderBy(r => int.Parse(VIF.get_device(session, r))).ToList();
        if (vifs.Count == 0) throw new Exception($"{vmName} has no network interface to accelerate");
        foreach (var existing in PVS_proxy.get_all_records(session).Values)
            if (existing.VIF.Equals(vifs[0]))
                throw new Exception($"{vmName} is already accelerated by site " +
                                    $"'{PVS_site.get_name_label(session, existing.site)}'");

        var site = PVS_site.introduce(session, "sdk-example-pvs", "Created by the SDK examples", "");
        PVS_server.introduce(session, new[] { "203.0.113.90" }, 6910, 6930, site);

        // The read cache should be on LOCAL storage. The point of the accelerator is to keep reads off
        // the network; the server does not enforce that, but a cache on shared storage rarely makes
        // sense and can't be shared between hosts anyway.
        foreach (var hostRef in Host.get_all(session))
        {
            var local = LocalSr(session, hostRef);
            if (local == null) continue;
            PVS_cache_storage.create(session, new PVS_cache_storage
            {
                host = hostRef,
                SR = local,
                site = site,
                size = 10L * 1024 * 1024 * 1024,
            });
        }

        // A proxy may only sit on the VM's LOWEST-numbered NIC, hence sorting by device above rather
        // than taking VIFs[0] — the list comes back in creation order, which is the same thing only by
        // luck.
        var proxy = PVS_proxy.create(session, site, vifs[0]);

        var record = PVS_site.get_record(session, site);
        Console.WriteLine($"Site '{record.name_label}' with {record.cache_storage.Count} cache(s) "
                          + $"and {record.servers.Count} server(s)");
        // "caching" means it is actually accelerating. A site with no cache storage reports
        // "initialised", and a proxy on a VM whose NIC is unplugged reports "stopped".
        Console.WriteLine($"  {VM.get_name_label(session, vm)}: {PVS_proxy.get_status(session, proxy)}");

        // Forgetting the site only cascades its cache storage - a running proxy or a server it still has
        // makes forget refuse with PVS_SITE_CONTAINS_RUNNING_PROXIES/_SERVERS, so tear those down
        // ourselves first, in the same order every real PVS teardown uses.
        PVS_proxy.destroy(session, proxy);
        foreach (var serverRef in PVS_site.get_servers(session, site)) PVS_server.forget(session, serverRef);
        PVS_site.forget(session, site);
        Console.WriteLine("OK: configure-pvs-accelerator");
        session.logout();
    }

    /// <summary>The host's own non-ISO storage, found through its PBDs.</summary>
    private static XenRef<SR> LocalSr(Session session, XenRef<Host> host)
    {
        foreach (var pbdRef in Host.get_PBDs(session, host))
        {
            // Keep the REF and read the record through it: a record fetched by get_record does not
            // carry its own opaque_ref, so reaching for sr.opaque_ref afterwards hands you a null.
            var srRef = PBD.get_SR(session, pbdRef);
            var sr = SR.get_record(session, srRef);
            if (!sr.shared && sr.content_type != "iso" && sr.type != "udev")
                return srRef;
        }
        return null;
    }
}
