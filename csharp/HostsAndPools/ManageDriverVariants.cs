using System;
using System.Linq;
using XenAPI;
using Console = System.Console; // XenAPI also defines a Console class

namespace XenServerWorkflows;

internal static partial class Workflows
{
    /// <summary>
    /// Inspect a host's device drivers and choose which variant of one to use, seeing the difference between
    /// the variant that is selected and the one currently loaded.
    /// </summary>
    public static void ManageDriverVariants(string url, string user, string password)
    {
        var session = Connect(url, user, password);
        var host = Pool.get_master(session, Pool.get_all(session)[0].opaque_ref).opaque_ref;

        // A driver can ship in several variants — a vendor build alongside the one in the
        // distribution, say. One is SELECTED (what the host will load) and one is ACTIVE (what it has
        // loaded); they differ until the host reboots, which is what makes selecting a variant a
        // scheduled change rather than an immediate one.
        var drivers = Host_driver.get_all_records(session)
            .Where(kv => kv.Value.host.opaque_ref == host)
            .OrderBy(kv => kv.Value.name).ToList();
        Console.WriteLine($"{Host.get_name_label(session, host)} has {drivers.Count} driver(s)");
        foreach (var (_, driver) in drivers.Take(3))
            Console.WriteLine($"  {driver.name,-14} {driver.type,-10} {driver.variants.Count} variant(s), " +
                $"active={VariantName(session, driver.active_variant.opaque_ref)}");

        // Select a variant explicitly. It becomes the selected one immediately; whether it is also
        // active depends on whether the hardware is present and the driver already loaded.
        // Host_driver.select refuses a variant whose hardware isn't present (HOST_DRIVER_NO_HARDWARE) -
        // and a host lists drivers for plenty of devices it doesn't have - so pick a driver for
        // hardware this host actually has, and one of its variants that is usable.
        var usable = drivers
            .SelectMany(kv => kv.Value.variants.Select(v => (driverRef: kv.Key, variant: v)))
            .Where(p => Driver_variant.get_hardware_present(session, p.variant.opaque_ref))
            .ToList();
        if (usable.Count == 0)
            throw new Exception($"no driver on {Host.get_name_label(session, host)} has a variant for hardware it has");
        var (chosenRef, chosenVariant) = usable[0];
        var variant = chosenVariant.opaque_ref;
        Host_driver.select(session, chosenRef.opaque_ref, variant);
        var after = Host_driver.get_record(session, chosenRef.opaque_ref);
        Console.WriteLine($"  {after.name}: selected {VariantName(session, after.selected_variant.opaque_ref)}, " +
            $"active {VariantName(session, after.active_variant.opaque_ref)}");

        Console.WriteLine("OK: manage-driver-variants");
        session.logout();
    }

    /// <summary>A driver variant's name, tolerating the null reference an unloaded driver has.</summary>
    private static string VariantName(Session session, string variantRef) =>
        !string.IsNullOrEmpty(variantRef) && variantRef != "OpaqueRef:NULL"
            ? Driver_variant.get_name(session, variantRef) : "(none)";
}
