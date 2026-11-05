using System;
using System.Collections.Generic;
using System.Linq;
using System.Xml.Linq;
using XenAPI;
using Console = System.Console; // XenAPI also defines a Console class

namespace XenServerWorkflows;

internal static partial class Workflows
{
    /// <summary>
    /// Connect a shared storage repository to a fibre-channel (HBA) LUN: discover the LUNs the host can see
    /// with a deliberately failing probe, then create the SR by SCSI ID. Creating the SR formats the LUN.
    /// </summary>
    /// <example>
    /// <code>
    /// Workflows.CreateHbaSr("https://xenserver", "root", password);
    /// </code>
    /// </example>
    /// <remarks>
    /// <para>
    /// Connect a shared SR to a fibre-channel (HBA) LUN, discovering it the way the New SR wizard does:
    /// probing with no SCSIid fails on purpose and lists every LUN the backend can see.
    /// </para>
    /// <para>
    /// SR.create formats the chosen LUN - this is destructive, so pick carefully on a real target.
    /// </para>
    /// </remarks>
    public static void CreateHbaSr(string url, string user, string password, string scsiId = "",
        string srName = "sdk-example-hba")
    {
        const long GiB = 1024L * 1024 * 1024;
        var session = Connect(url, user, password);
        var host = Host.get_all(session)[0].opaque_ref;

        // The root element varies by backend; find BlockDevice entries by tag wherever they are.
        var devlistXml = XDocument.Parse(ProbeForFailure(session, host, new Dictionary<string, string>(), "lvmohba"));
        // SR.create formats the LUN: on shared FC storage name yours (scsiId); with none, the first is taken.
        var device = devlistXml.Descendants("BlockDevice")
                         .FirstOrDefault(d => scsiId == "" || d.Element("SCSIid")!.Value == scsiId)
                     ?? throw new Exception($"no LUN with SCSIid {scsiId} is visible to this host");
        scsiId = device.Element("SCSIid")!.Value;
        var path = device.Element("path")!.Value;
        Console.WriteLine($"Discovered LUN: SCSIid {scsiId} on {path}");

        // SCSIid is all lvmohba needs. (The probe's <path> is for display: on a real host it reads
        // like "/dev/sde [sdc] [sdg] [sdi]", one entry per path.)
        var dc = new Dictionary<string, string> { ["SCSIid"] = scsiId };

        // SCSIid alone is also enough to probe the LUN itself: an <SR> in the answer means one is already
        // there, and SR.create would format it. Reattach that SR rather than destroying it.
        var srListXml = XDocument.Parse(SR.probe(session, host, dc, "lvmohba", new Dictionary<string, string>()));
        var existing = srListXml.Descendants("SR").FirstOrDefault();
        if (existing != null)
            throw new Exception($"LUN {scsiId} already holds SR {existing.Element("UUID")!.Value.Trim()}; "
                + "creating an SR here would format it - reattach the existing SR instead of creating a new one");

        var sr = SR.create(session, host, dc, 0, srName, "HBA SR created by the SDK example",
            "lvmohba", "user", true, new Dictionary<string, string>());
        Console.WriteLine($"Created SR: {SR.get_uuid(session, sr)} ({SR.get_physical_size(session, sr) / GiB} GiB)");
        // Tidy up: this example created the SR, so destroy it - a forgotten SR would stay on the LUN.
        // SR.destroy needs it detached from every host first.
        foreach (var pbd in SR.get_PBDs(session, sr))
            if (PBD.get_currently_attached(session, pbd.opaque_ref))
                PBD.unplug(session, pbd.opaque_ref);
        SR.destroy(session, sr);
        Console.WriteLine("OK: create-hba-sr");
        session.logout();
    }
}
