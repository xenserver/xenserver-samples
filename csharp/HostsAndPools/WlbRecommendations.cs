using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using XenAPI;
using Console = System.Console; // XenAPI also defines a Console class

namespace XenServerWorkflows;

internal static partial class Workflows
{
    /// <summary>
    /// Point the pool at a workload-balancing appliance, read its placement recommendations for the pool and
    /// for one VM, then disconnect it.
    /// </summary>
    /// <example>
    /// <code>
    /// Workflows.WlbRecommendations("https://xenserver", "root", password, "web-01",
    /// Workflows.wlbHostPort: "192.0.2.60:30601", wlbUsername: "wlbuser", wlbPassword: "wlbpass",
    /// Workflows.wlbCertificate: "wlb-appliance.pem");
    /// </code>
    /// </example>
    /// <remarks>
    /// <para>
    /// Connect a workload-balancing appliance and read its placement advice. Needs a real, reachable WLB
    /// appliance: pool.initialize_wlb makes a synchronous HTTP call to it and raises
    /// WLB_CONNECTION_REFUSED/WLB_CONNECTION_RESET if it can't connect - there is no way to fake this with a
    /// placeholder. wlbHostPort is host:port, with no URL scheme - that is the real wire format (xe
    /// pool-initialize-wlb wlb_url="10.x.x.x:30601" ...), not a URL.
    /// </para>
    /// <para>
    /// The pool checks the appliance's TLS certificate (pool.wlb_verify_cert), and only against the
    /// certificates installed with Pool.certificate_install - not install_trusted_certificate's. A fresh
    /// appliance has a self-signed one, so pass it as wlbCertificate (a PEM file): without it initialize_wlb
    /// fails with INTERNAL_ERROR "Connection failed: configuration failed." and no hint that the certificate
    /// is the reason.
    /// </para>
    /// </remarks>
    public static void WlbRecommendations(string url, string user, string password, string vmName,
        string wlbHostPort = "wlb.example:8012", string wlbUsername = "wlbuser", string wlbPassword = "wlbpass",
        string wlbCertificate = "")
    {
        var session = Connect(url, user, password);
        var poolRef = Pool.get_all(session)[0].opaque_ref;

        var certName = "";
        if (wlbCertificate != "")
        {
            certName = "sdk-example-wlb.pem";
            Pool.certificate_install(session, certName, File.ReadAllText(wlbCertificate)); // pool-wide: no pool argument
        }
        Pool.initialize_wlb(session, wlbHostPort, wlbUsername, wlbPassword, user, password);
        try
        {
            // Initializing connects the pool to the appliance but leaves balancing off: every WLB call
            // after this would fail WLB_DISABLED until it's switched on.
            Pool.set_wlb_enabled(session, poolRef, true);
            Console.WriteLine($"WLB: {Pool.get_wlb_url(session, poolRef)}");

            // Read BY POSITION, and the two calls do not share a shape. The pool's recommendations are
            // keyed by VM and say where to move it: [0] "wlb", [1] the destination host's UUID (a uuid,
            // not a ref), [2] and [3] ids, [4] the reason.
            foreach (var entry in Pool.retrieve_wlb_recommendations(session))
                Console.WriteLine($"  move {VM.get_name_label(session, entry.Key.opaque_ref)} " +
                                  $"-> host {entry.Value[1]} ({entry.Value[4]})");

            // A VM's own recommendations are keyed by host and star-rate each as a destination:
            // [0] "wlb", [1] the rating - higher is better (a real appliance rated hosts 6.1 here, so not
            // capped at five). Right after connecting, the appliance is still discovering the pool:
            // WLB_INTERNAL_ERROR 4024 ("Pool discovery has not been started"), 4025 ("... has not been
            // completed"), then 4016 ("WLB does not have current metrics") - keep asking.
            var vm = VM.get_by_name_label(session, vmName)[0];
            var deadline = DateTime.UtcNow.AddMinutes(10);
            Dictionary<XenRef<Host>, string[]> vmRecs;
            while (true)
            {
                try
                {
                    vmRecs = VM.retrieve_wlb_recommendations(session, vm.opaque_ref);
                    break;
                }
                catch (Failure e)
                {
                    if (e.ErrorDescription[0] != "WLB_INTERNAL_ERROR" ||
                        !new[] { "4024", "4025", "4016" }.Contains(e.ErrorDescription[1]) ||
                        DateTime.UtcNow > deadline) throw;
                    System.Threading.Thread.Sleep(15000);
                }
            }
            foreach (var entry in vmRecs)
                Console.WriteLine($"  {Host.get_name_label(session, entry.Key.opaque_ref)} " +
                                  $"rated {entry.Value[1]}");

            // The appliance's own settings are read and written as one flat map of strings. Send a
            // nightly reporting schedule, then read the configuration back to confirm it took.
            Pool.send_wlb_configuration(session, new Dictionary<string, string> { ["ReportingCronString"] = "0 3 * * *" });
            var wlbConfig = Pool.retrieve_wlb_configuration(session);
            Console.WriteLine("  appliance configuration: " +
                string.Join(", ", wlbConfig.OrderBy(kv => kv.Key).Select(kv => $"{kv.Key}={kv.Value}")));
        }
        finally
        {
            // Disconnect from the appliance however the above went, or the pool stays attached to it.
            Pool.deconfigure_wlb(session);
            if (certName != "") Pool.certificate_uninstall(session, certName);
        }
        Console.WriteLine("OK: wlb-recommendations");
        session.logout();
    }
}
