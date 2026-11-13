using System.Linq;
using XenAPI;
using Console = System.Console; // XenAPI also defines a Console class

namespace XenServerWorkflows;

internal static partial class Workflows
{
    /// <summary>
    /// Read a host's software version, edition and CPU topology (sockets and cores).
    /// </summary>
    /// <example>
    /// <code>
    /// Workflows.HostInfo("https://xenserver", "root", password);
    /// </code>
    /// </example>
    public static void HostInfo(string url, string user, string password)
    {
        var session = Connect(url, user, password);
        var (hostRef, host) = Host.get_all_records(session).First();
        var sw = host.software_version;
        var cpu = host.cpu_info;
        Console.WriteLine($"Host:     {host.name_label}");
        Console.WriteLine($"Version:  {(sw.TryGetValue("product_version", out var pv) ? pv : "?")}");
        Console.WriteLine($"Edition:  {host.edition}");
        Console.WriteLine($"CPUs:     {(cpu.TryGetValue("cpu_count", out var cc) ? cc : "?")} across " +
                          $"{(cpu.TryGetValue("socket_count", out var sc) ? sc : "?")} socket(s)");
        // The physical identity, straight off the host's DMI/SMBIOS tables. The serial number is what
        // you quote to the hardware vendor, so it is the one field here that identifies this machine
        // and not just its model.
        var bios = host.bios_strings;
        string Bios(string k) => bios.TryGetValue(k, out var v) ? v : "?";
        Console.WriteLine($"Hardware: {Bios("system-manufacturer")} {Bios("system-product-name")}");
        Console.WriteLine($"Serial:   {Bios("system-serial-number")}");
        Console.WriteLine($"BIOS:     {Bios("bios-version")}");
        Console.WriteLine("OK: host-info");
        session.logout();
    }
}
