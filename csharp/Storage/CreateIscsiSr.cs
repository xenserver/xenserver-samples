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
    /// Connect a storage repository to a LUN on an iSCSI target, discovering the target's IQNs and then the
    /// LUNs behind one. Creating the SR formats the LUN, and a shared array offers many targets, so name
    /// yours with target_iqn; if the target behind it offers more than one LUN, name yours with scsi_id
    /// too.
    /// </summary>
    /// <example>
    /// <code>
    /// Workflows.CreateIscsiSr("https://xenserver", "root", password, "192.0.2.30", null, null, null);
    /// </code>
    /// </example>
    /// <remarks>
    /// <para>
    /// Connect an SR to a LUN on the iSCSI target, discovering the IQN and the LUN first: a device-config
    /// that's missing a piece makes the backend fail on purpose, and the failure carries an XML fragment
    /// listing what it needs next.
    /// </para>
    /// <para>
    /// SR.create formats the chosen LUN - this is destructive, so pick carefully on a real target: pass
    /// targetIqn to name yours (see ChooseTargetIqn), and scsiId too if more than one LUN is offered behind
    /// it (see ChooseLun). Before creating, this probes the chosen LUN itself to make sure it is not already
    /// in use by another SR - formatting over one would destroy it.
    /// </para>
    /// <para>
    /// The CHAP password (if any) travels as a Secret, not plaintext device-config, as CreateSmbSr already
    /// does for its share password.
    /// </para>
    /// </remarks>
    public static void CreateIscsiSr(string url, string user, string password, string target,
        int? port, string chapUser, string chapPassword, string targetIqn = null, string scsiId = null,
        string srName = "sdk-example-iscsi")
    {
        const long GiB = 1024L * 1024 * 1024;
        var session = Connect(url, user, password);
        var host = Host.get_all(session)[0];
        var dc = new Dictionary<string, string> { ["target"] = target };
        if (port.HasValue) dc["port"] = port.Value.ToString();
        XenRef<Secret> secret = null;
        if (!string.IsNullOrEmpty(chapUser))
        {
            dc["chapuser"] = chapUser;
            secret = Secret.create(session, new Secret
            {
                value = chapPassword,
                other_config = new Dictionary<string, string>(),
            });
            dc["chappassword_secret"] = Secret.get_uuid(session, secret);
        }

        try
        {
            // First failing probe: target only -> the backend lists the IQNs it offers.
            var iqnXml = XDocument.Parse(ProbeForFailure(session, host, dc, "lvmoiscsi"));
            dc["targetIQN"] = ChooseTargetIqn(iqnXml, target, targetIqn);
            Console.WriteLine($"Discovered IQN: {dc["targetIQN"]}");

            // Second failing probe: +targetIQN -> the backend lists the LUNs behind it. Real create also
            // carries LUNid whenever it is known.
            var lunXml = XDocument.Parse(ProbeForFailure(session, host, dc, "lvmoiscsi"));
            var luns = lunXml.Descendants("LUN").ToList();
            var lun = ChooseLun(luns, scsiId);
            dc["SCSIid"] = lun.Element("SCSIid")!.Value;
            var lunId = lun.Element("LUNid");
            dc["LUNid"] = lunId != null ? lunId.Value : luns.IndexOf(lun).ToString();
            Console.WriteLine($"Discovered LUN {dc["LUNid"]} (SCSIid {dc["SCSIid"]})");

            // The device-config is now complete enough to create from - which means it is also complete
            // enough to probe the LUN itself: an <SR> in the answer means one is already there, and
            // SR.create would format it. Reattach that SR rather than destroying it.
            var srListXml = XDocument.Parse(SR.probe(session, host, dc, "lvmoiscsi", new Dictionary<string, string>()));
            var existing = srListXml.Descendants("SR").FirstOrDefault();
            if (existing != null)
                throw new Exception($"LUN {dc["SCSIid"]} already holds SR {existing.Element("UUID")!.Value.Trim()}; "
                    + "creating an SR here would format it - reattach the existing SR instead of creating a new one");

            var sr = SR.create(session, host, dc, 0, srName, "iSCSI SR created by the SDK example",
                "lvmoiscsi", "user", true, new Dictionary<string, string>());
            Console.WriteLine($"Created SR: {SR.get_uuid(session, sr)} ({SR.get_physical_size(session, sr) / GiB} GiB)");
            // Tidy up: this example created the SR, so destroy it - a forgotten SR would stay on the LUN.
            // SR.destroy needs it detached from every host first.
            foreach (var pbd in SR.get_PBDs(session, sr))
                if (PBD.get_currently_attached(session, pbd))
                    PBD.unplug(session, pbd);
            SR.destroy(session, sr);
        }
        finally
        {
            if (secret != null) Secret.destroy(session, secret);
        }
        Console.WriteLine("OK: create-iscsi-sr");
        session.logout();
    }

    /// <summary>
    /// Pick the IQN from an iSCSI discovery probe: the caller's, if named (it must be one the target offers),
    /// else the first. An array usually offers many targets - one per LUN, often belonging to different users
    /// - so on shared storage always name yours: SR.create formats the LUN behind it.
    /// </summary>
    private static string ChooseTargetIqn(XDocument iqnXml, string target, string targetIqn)
    {
        var offered = iqnXml.Descendants("TargetIQN").Select(e => e.Value).ToList();
        if (!string.IsNullOrEmpty(targetIqn) && !offered.Contains(targetIqn))
            throw new Exception($"target {target} does not offer IQN {targetIqn}");
        return string.IsNullOrEmpty(targetIqn) ? offered.First() : targetIqn;
    }

    /// <summary>
    /// Pick the LUN behind the chosen IQN: the caller's SCSIid, if named (it must be one on offer), else the
    /// one LUN, if that target offers only one. Choose a LUN automatically only when exactly one is on
    /// offer, and otherwise make the caller choose - picking blindly on a shared target risks formatting
    /// someone else's disk.
    /// </summary>
    private static XElement ChooseLun(List<XElement> luns, string scsiId)
    {
        if (!string.IsNullOrEmpty(scsiId))
        {
            var lun = luns.FirstOrDefault(l => l.Element("SCSIid")!.Value == scsiId);
            if (lun == null)
                throw new Exception($"target does not offer a LUN with SCSIid {scsiId}; offered: "
                    + string.Join(", ", luns.Select(l => l.Element("SCSIid")!.Value)));
            return lun;
        }
        if (luns.Count == 1) return luns[0];
        var offered = string.Join(", ", luns.Select(l => $"{l.Element("SCSIid")!.Value} ({l.Element("size")!.Value} bytes)"));
        throw new Exception($"target offers {luns.Count} LUNs; name one with scsiId: {offered}");
    }
}
