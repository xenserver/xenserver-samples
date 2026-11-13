using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Net.Http;
using System.Text.Json;
using XenAPI;
using Console = System.Console; // XenAPI also defines a Console class

namespace XenServerWorkflows;

internal static partial class Workflows
{
    /// <summary>
    /// Pull recent host performance samples from the RRD archives over the performance-data HTTP API, parse
    /// the legends and data, and summarise a metric (here the peak PVS Accelerator cache-space utilisation
    /// per host).
    /// </summary>
    public static void RrdMetrics(string url, string user, string password)
    {
        var session = Connect(url, user, password);
        var nameByUuid = Host.get_all_records(session).Values.ToDictionary(h => h.uuid, h => h.name_label);

        // The RRD time-series isn't a XenAPI call; read rrd_updates over HTTP. Legends look like
        // "AVERAGE:host:<uuid>:<datasource>"; values[] aligns to legend[].
        var start = DateTimeOffset.UtcNow.ToUnixTimeSeconds() - 300;
        using var http = new HttpClient(new HttpClientHandler
        {
            ServerCertificateCustomValidationCallback = (_, _, _, _) => true
        });
        http.DefaultRequestHeaders.Add("accept", "application/json");
        var json = http.GetStringAsync($"{url}/rrd_updates?session_id={session.opaque_ref}&host=true&start={start}").Result;

        using var doc = JsonDocument.Parse(json);
        var legends = doc.RootElement.GetProperty("meta").GetProperty("legend")
            .EnumerateArray().Select(e => e.GetString()!).ToArray();
        var peak = new Dictionary<string, double>();
        foreach (var point in doc.RootElement.GetProperty("data").EnumerateArray())
        {
            var values = point.GetProperty("values");
            for (int k = 0; k < legends.Length; k++)
            {
                var parts = legends[k].Split(':');
                if (parts[1] == "host" && parts[3] == "pvsaccelerator_space_utilization")
                {
                    // A host sends each value as a string ("0.0", or "NaN" for a gap in the series).
                    var v = values[k].ValueKind == JsonValueKind.String
                        ? double.Parse(values[k].GetString()!, CultureInfo.InvariantCulture)
                        : values[k].GetDouble();
                    if (double.IsNaN(v)) continue;
                    if (!peak.TryGetValue(parts[2], out var cur) || v > cur) peak[parts[2]] = v;
                }
            }
        }
        foreach (var (uuid, p) in peak)
            Console.WriteLine($"  {nameByUuid[uuid]}: peak PVS cache utilisation {p:F0}%");
        Console.WriteLine("OK: rrd-metrics");
        session.logout();
    }
}
