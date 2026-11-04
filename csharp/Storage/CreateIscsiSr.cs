using System;
using System.Collections.Generic;
using System.Linq;
using System.Xml.Linq;
using XenAPI;
using Console = System.Console; // XenAPI also defines a Console class

namespace XenServerWorkflows;

internal static partial class Workflows
{
    /// <summary> Connect a storage repository to a LUN on an iSCSI target, discovering the target's IQNs and
    /// then the LUNs behind one, as the New SR wizard does. Creating the SR formats the LUN, and a shared
    /// array offers many targets, so name yours with target_iqn. </summary> <example> <code>
    /// Workflows.CreateIscsiSr("https://xenserver", "root", password, "192.0.2.30", null, null, null);
    /// </code> </example> <remarks> <para> Connect an SR to a LUN on the iSCSI target, discovering the IQN
    /// and the LUN the way the New SR wizard does: a device-config that's missing a piece makes the backend
    /// fail on purpose, and the failure carries an XML fragment listing what it needs next. </para> <para>
    /// SR.create formats the chosen LUN - this is destructive, so pick carefully on a real target: pass
    /// targetIqn to name yours (see ChooseTargetIqn). </para> </remarks>
    public static void CreateIscsiSr(string url, string user, string password, string target,
        int? port, string chapUser, string chapPassword, string targetIqn = null,
        string srName = "sdk-example-iscsi")
    {
        const long GiB = 1024L * 1024 * 1024;
        var session = Connect(url, user, password);
        var host = Host.get_all(session)[0].opaque_ref;
        var dc = new Dictionary<string, string> { ["target"] = target };
        if (port.HasValue) dc["port"] = port.Value.ToString();
        if (!string.IsNullOrEmpty(chapUser))
        {
            dc["chapuser"] = chapUser;
            dc["chappassword"] = chapPassword;
        }

        // First failing probe: target only -> the backend lists the IQNs it offers.
        var iqnXml = XDocument.Parse(ProbeForFailure(session, host, dc, "lvmoiscsi"));
        dc["targetIQN"] = ChooseTargetIqn(iqnXml, target, targetIqn);
        Console.WriteLine($"Discovered IQN: {dc["targetIQN"]}");

        // Second failing probe: +targetIQN -> the backend lists the LUNs behind it. Real create also
        // carries LUNid whenever it is known.
        var lunXml = XDocument.Parse(ProbeForFailure(session, host, dc, "lvmoiscsi"));
        var luns = lunXml.Descendants("LUN").ToList();
        var lun = luns[0];
        dc["SCSIid"] = lun.Element("SCSIid")!.Value;
        var lunId = lun.Element("LUNid");
        dc["LUNid"] = lunId != null ? lunId.Value : luns.IndexOf(lun).ToString();
        Console.WriteLine($"Discovered LUN {dc["LUNid"]} (SCSIid {dc["SCSIid"]})");

        var sr = SR.create(session, host, dc, 0, srName, "iSCSI SR created by the SDK example",
            "lvmoiscsi", "user", true, new Dictionary<string, string>());
        Console.WriteLine($"Created SR: {SR.get_uuid(session, sr)} ({SR.get_physical_size(session, sr) / GiB} GiB)");
        DetachAndForgetSr(session, sr);
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
}
