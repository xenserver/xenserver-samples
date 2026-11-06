using System;
using System.Collections.Generic;
using System.Text.Json;
using XenAPI;
using Console = System.Console; // XenAPI also defines a Console class

namespace XenServerWorkflows;

internal static partial class Workflows
{
    /// <summary>
    /// Configure a host's SNMP agent through the monitoring plugin: read its configuration, enable it with a
    /// community string, then read the configuration and running status back.
    /// </summary>
    /// <example>
    /// <code>
    /// Workflows.ConfigureSnmp("https://xenserver", "root", password, trapDestination: "192.0.2.50");
    /// </code>
    /// </example>
    public static void ConfigureSnmp(string url, string user, string password,
        string trapDestination = "192.0.2.50")
    {
        var session = Connect(url, user, password);
        // nmss is the list of real trap destinations SNMP notifications go to - an empty list never
        // configures where traps actually go, which is the whole point of "configure SNMP monitoring".
        var config =
            "{\"common\":{\"enabled\":\"yes\",\"debug_log\":\"no\"}," +
            "\"agent\":{\"v2c\":\"yes\",\"v3\":\"no\",\"community\":\"sdk-community\",\"user_name\":\"\"," +
            "\"authentication_password\":\"\",\"authentication_protocol\":\"\"," +
            "\"privacy_password\":\"\",\"privacy_protocol\":\"\"}," +
            // Each trap destination needs a uuid of its own: the plugin refuses the whole config without one.
            $"\"nmss\":[{{\"uuid\":\"{Guid.NewGuid()}\",\"address\":\"{trapDestination}\",\"port\":162,\"v2c\":\"yes\",\"v3\":\"no\"," +
            "\"community\":\"sdk-community\",\"user_name\":\"\",\"authentication_password\":\"\"," +
            "\"authentication_protocol\":\"\",\"privacy_password\":\"\",\"privacy_protocol\":\"\"}]}";
        // Plugin calls are per-host, so configure every host, and restore each one to disabled again
        // afterwards.
        foreach (var host in Host.get_all(session))
        {
            string Snmp(string fn, Dictionary<string, string> args) =>
                Host.call_plugin(session, host, "snmp", fn, args);
            // The plugin reports a refused config in its answer, not as an API error: check it.
            using (var answer = JsonDocument.Parse(Snmp("set-config", new() { ["config"] = config })))
                if (answer.RootElement.GetProperty("code").GetInt32() != 0)
                    throw new Exception("set-config refused the configuration: "
                                        + answer.RootElement.GetProperty("message").GetString());
            using var status = JsonDocument.Parse(Snmp("status", new()));
            using var cfg = JsonDocument.Parse(Snmp("get-config", new()));
            var result = status.RootElement.GetProperty("result");
            var agentCfg = cfg.RootElement.GetProperty("result");
            var nmss = agentCfg.GetProperty("nmss");
            var label = Host.get_name_label(session, host);
            Console.WriteLine($"{label}: SNMP enabled: {result.GetProperty("enabled").GetString()} / " +
                              $"{result.GetProperty("active").GetString()}");
            Console.WriteLine($"  community: {agentCfg.GetProperty("agent").GetProperty("community").GetString()}, " +
                              $"trap destination: {(nmss.GetArrayLength() > 0 ? nmss[0].GetProperty("address").GetString() : "(none)")}");
            Snmp("set-config", new() { ["config"] = "{\"common\":{\"enabled\":\"no\"}}" }); // restore
        }
        Console.WriteLine("OK: configure-snmp");
        session.logout();
    }
}
