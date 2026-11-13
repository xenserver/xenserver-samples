using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Net.Http;
using System.Xml.Linq;
using XenAPI;
using Console = System.Console; // XenAPI also defines a Console class

namespace XenServerWorkflows;

internal static partial class Workflows
{
    /// <summary>
    /// Gather a host's diagnostic bundle: read the catalogue of sections it can report on, download the whole
    /// bundle, then download a smaller one covering only the sections you pick.
    /// </summary>
    public static void ServerStatusReport(string url, string user, string password)
    {
        var session = Connect(url, user, password);

        // Report on the coordinator. Each host answers for itself, so which one you ask decides whose
        // logs you get — support normally wants every host, one download each.
        var host = Pool.get_master(session, Pool.get_all(session).First());
        Console.WriteLine($"Status report for {Host.get_name_label(session, host)}");

        // The host publishes a catalogue of the sections it can report on, each with a size estimate and
        // whether it may contain personal data, so a client can offer an informed choice rather than
        // hard-coding the list.
        var keys = new List<string>();
        var defaults = new List<string>();
        foreach (var capability in XDocument.Parse(
                     Host.get_system_status_capabilities(session, host)).Root!.Elements())
        {
            var key = (string)capability.Attribute("key")!;
            keys.Add(key);
            if ((string)capability.Attribute("default-checked")! == "yes") defaults.Add(key);
            Console.WriteLine($"  {key,-22} "
                              + $"max {(string)capability.Attribute("max-size")!,9} bytes  "
                              + $"default={(string)capability.Attribute("default-checked")!,-3} "
                              + $"pii={(string)capability.Attribute("pii")!}");
        }

        // Take the sections the host marks default-checked: asking for every section can mean gigabytes (VM
        // memory dumps, every log) and a long wait while the host builds it.
        var whole = FetchStatusReport(session, url, defaults);
        Console.WriteLine($"default sections ({defaults.Count} of {keys.Count}): {whole} bytes");

        // Pick a real, small section from the host's own catalogue rather than assuming a name: the
        // catalogue is server-defined (xen-bugtool's own --capabilities output), not a fixed client
        // list, and "xenserver-config" isn't one of the real keys any host actually publishes.
        var subsetKey = keys.FirstOrDefault(k => k is "firstboot" or "network-status") ?? keys[0];
        var subset = FetchStatusReport(session, url, new[] { subsetKey });
        Console.WriteLine($"{subsetKey} only:   {subset} bytes");
        if (subset >= whole)
            Console.WriteLine("  ERROR: selecting fewer sections did not produce a smaller bundle");

        Console.WriteLine("OK: server-status-report");
        session.logout();
    }

    /// <summary>
    /// Download the bundle for the given capability keys (a tar archive) to a temp file, streaming it - a
    /// report can be large - and return its size. This example then deletes it; you'd keep it.
    /// </summary>
    private static long FetchStatusReport(Session session, string url, IEnumerable<string> entries)
    {
        var path = Path.Combine(Path.GetTempPath(), $"sdk-example-status-{Guid.NewGuid():N}.tar");
        try
        {
            using var client = InsecureHttpClient();
            // A full report (all sections) can take well over the default 5-minute client timeout on a
            // real host with a lot to report on; this download alone gets a much longer allowance.
            client.Timeout = TimeSpan.FromMinutes(30);
            using var response = client.GetAsync(
                $"{url}/system-status?session_id={session.opaque_ref}&output=tar"
                + $"&entries={string.Join(",", entries)}",
                HttpCompletionOption.ResponseHeadersRead).Result;
            response.EnsureSuccessStatusCode();
            using (var httpStream = response.Content.ReadAsStreamAsync().Result)
            using (var fileStream = File.Create(path))
                httpStream.CopyTo(fileStream);
            return new FileInfo(path).Length;
        }
        finally
        {
            File.Delete(path);
        }
    }
}
