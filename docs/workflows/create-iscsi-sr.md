<!-- Generated from workflows.json, the example sources and a run of each example. Edit those, not this file. -->

# Create an iSCSI SR

Connect a storage repository to a LUN on an iSCSI target, discovering the target's IQNs and then the LUNs behind one, as the New SR wizard does. Creating the SR formats the LUN, and a shared array offers many targets, so name yours with target_iqn.

**Requires:** an iSCSI target.

**Caution:** formats the LUN it uses (name it with scsi_id; it refuses a LUN that already holds an SR) and destroys the new SR again afterwards.

Workflow `create-iscsi-sr`. [All workflows](README.md) · [Connecting](connecting.md)

## C# (.NET)

Source: [`csharp/Storage/CreateIscsiSr.cs`](../../csharp/Storage/CreateIscsiSr.cs)

```csharp
/// <summary>
/// Connect a storage repository to a LUN on an iSCSI target, discovering the target's IQNs and then the
/// LUNs behind one, as the New SR wizard does. Creating the SR formats the LUN, and a shared array offers
/// many targets, so name yours with target_iqn; if the target behind it offers more than one LUN, name
/// yours with scsi_id too.
/// </summary>
/// <example>
/// <code>
/// Workflows.CreateIscsiSr("https://xenserver", "root", password, "192.0.2.30", null, null, null);
/// </code>
/// </example>
/// <remarks>
/// <para>
/// Connect an SR to a LUN on the iSCSI target, discovering the IQN and the LUN the way the New SR wizard
/// does: a device-config that's missing a piece makes the backend fail on purpose, and the failure
/// carries an XML fragment listing what it needs next.
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
    var host = Host.get_all(session)[0].opaque_ref;
    var dc = new Dictionary<string, string> { ["target"] = target };
    if (port.HasValue) dc["port"] = port.Value.ToString();
    string secret = null;
    if (!string.IsNullOrEmpty(chapUser))
    {
        dc["chapuser"] = chapUser;
        secret = Secret.create(session, new Secret
        {
            value = chapPassword,
            other_config = new Dictionary<string, string>(),
        }).opaque_ref;
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
            if (PBD.get_currently_attached(session, pbd.opaque_ref))
                PBD.unplug(session, pbd.opaque_ref);
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
/// one LUN, if that target offers only one. The New SR wizard auto-selects a LUN only when exactly one is
/// on offer, and otherwise makes the caller choose - picking blindly on a shared target risks formatting
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
```

<details><summary>Example output</summary>

```text
Discovered IQN: iqn.2009-01.com.example:target-0
Discovered LUN 0 (SCSIid 360a980004265656d5f4a2d63764e5734)
Created SR: 00000001-0000-0000-b30a-000000000000 (200 GiB)
OK: create-iscsi-sr
```

</details>

## Python

Source: [`python/storage/create_iscsi_sr.py`](../../python/storage/create_iscsi_sr.py)

```python
"""Create an iSCSI SR.

Connect a storage repository to a LUN on an iSCSI target, discovering the target's IQNs and then the
LUNs behind one, as the New SR wizard does. Creating the SR formats the LUN, and a shared array
offers many targets, so name yours with target_iqn; if the target behind it offers more than one
LUN, name yours with scsi_id too.
"""

import xml.etree.ElementTree as ET

from connection import connect
from helpers import probe_for_failure


def create_iscsi_sr(url, username, password, target, port=None, chap_user=None, chap_password=None,
                     target_iqn=None, scsi_id=None, sr_name="sdk-example-iscsi"):
    """Connect an SR to a LUN on the iSCSI target, discovering the IQN and the LUN the way the New
    SR wizard does: a device-config that's missing a piece makes the backend fail on purpose, and
    the failure carries an XML fragment listing what it needs next.

    SR.create formats the chosen LUN - this is destructive, so pick carefully on a real target:
    pass target_iqn to name yours (see _choose_target_iqn), and scsi_id too if more than one LUN
    is offered behind it (see _choose_lun). Before creating, this probes the chosen LUN itself to
    make sure it is not already in use by another SR - formatting over one would destroy it.

    The CHAP password (if any) travels as a Secret, not plaintext device-config, as create-smb-sr
    already does for its share password."""
    GIB = 1024 * 1024 * 1024
    session = connect(url, username, password)
    host = session.xenapi.host.get_all()[0]
    dc = {"target": target}
    if port:
        dc["port"] = str(port)
    secret = None
    if chap_user:
        dc["chapuser"] = chap_user
        secret = session.xenapi.secret.create({"value": chap_password, "other_config": {}})
        dc["chappassword_secret"] = session.xenapi.secret.get_uuid(secret)

    try:
        # First failing probe: target only -> the backend lists the IQNs it offers.
        iqn_xml = ET.fromstring(probe_for_failure(session, host, dc, "lvmoiscsi"))
        dc["targetIQN"] = _choose_target_iqn(iqn_xml, target, target_iqn)
        print("Discovered IQN: %s" % dc["targetIQN"])

        # Second failing probe: +targetIQN -> the backend lists the LUNs behind it. Real create also
        # carries LUNid whenever it is known.
        lun_xml = ET.fromstring(probe_for_failure(session, host, dc, "lvmoiscsi"))
        luns = lun_xml.findall(".//LUN")
        lun = _choose_lun(luns, scsi_id)
        dc["SCSIid"] = lun.find("SCSIid").text
        lun_id = lun.find("LUNid")
        dc["LUNid"] = lun_id.text if lun_id is not None else str(luns.index(lun))
        print("Discovered LUN %s (SCSIid %s)" % (dc["LUNid"], dc["SCSIid"]))

        # The device-config is now complete enough to create from - which means it is also complete
        # enough to probe the LUN itself: an <SR> in the answer means one is already there, and
        # SR.create would format it. Reattach that SR rather than destroying it.
        srlist_xml = ET.fromstring(session.xenapi.SR.probe(host, dc, "lvmoiscsi", {}))
        existing = srlist_xml.find("SR")
        if existing is not None:
            raise RuntimeError("LUN %s already holds SR %s; creating an SR here would format it - "
                                "reattach the existing SR instead of creating a new one"
                                % (dc["SCSIid"], existing.find("UUID").text.strip()))

        sr = session.xenapi.SR.create(host, dc, "0", sr_name,
                                      "iSCSI SR created by the SDK example", "lvmoiscsi", "user", True, {})
        print("Created SR: %s (%d GiB)"
              % (session.xenapi.SR.get_uuid(sr), int(session.xenapi.SR.get_physical_size(sr)) // GIB))
        # Tidy up: this example created the SR, so destroy it - a forgotten SR would stay on the LUN.
        # SR.destroy needs it detached from every host first.
        for pbd in session.xenapi.SR.get_PBDs(sr):
            if session.xenapi.PBD.get_currently_attached(pbd):
                session.xenapi.PBD.unplug(pbd)
        session.xenapi.SR.destroy(sr)
    finally:
        if secret:
            session.xenapi.secret.destroy(secret)
    print("OK: create-iscsi-sr")
    session.logout()


def _choose_target_iqn(iqn_xml, target, target_iqn):
    """Pick the IQN from an iSCSI discovery probe: the caller's, if named (it must be one the target
    offers), else the first. An array usually offers many targets - one per LUN, often belonging to
    different users - so on shared storage always name yours: SR.create formats the LUN behind it."""
    offered = [e.text for e in iqn_xml.findall(".//TargetIQN")]
    if target_iqn and target_iqn not in offered:
        raise RuntimeError("target %s does not offer IQN %s" % (target, target_iqn))
    return target_iqn or offered[0]


def _choose_lun(luns, scsi_id):
    """Pick the LUN behind the chosen IQN: the caller's SCSIid, if named (it must be one on offer),
    else the one LUN, if that target offers only one. The New SR wizard auto-selects a LUN only when
    exactly one is on offer, and otherwise makes the caller choose - picking blindly on a shared
    target risks formatting someone else's disk."""
    if scsi_id:
        for lun in luns:
            if lun.find("SCSIid").text == scsi_id:
                return lun
        raise RuntimeError("target does not offer a LUN with SCSIid %s; offered: %s"
                            % (scsi_id, ", ".join(lun.find("SCSIid").text for lun in luns)))
    if len(luns) == 1:
        return luns[0]
    offered = ", ".join("%s (%s bytes)" % (lun.find("SCSIid").text, lun.find("size").text) for lun in luns)
    raise RuntimeError("target offers %d LUNs; name one with scsi_id: %s" % (len(luns), offered))
```

<details><summary>Example output</summary>

```text
Discovered IQN: iqn.2009-01.com.example:target-0
Discovered LUN 0 (SCSIid 360a980004265656d5f4a2d63764e5734)
Created SR: 00000001-0000-0000-690a-000000000000 (200 GiB)
OK: create-iscsi-sr
```

</details>

## Java

Source: [`java/src/main/java/com/xenserver/samples/storage/CreateIscsiSr.java`](../../java/src/main/java/com/xenserver/samples/storage/CreateIscsiSr.java)

```java
package com.xenserver.samples.storage;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.Host;
import com.xensource.xenapi.SR;
import com.xensource.xenapi.Secret;
import com.xensource.xenapi.Session;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.StringJoiner;

import static com.xenserver.samples.Helpers.firstTagText;
import static com.xenserver.samples.Helpers.parseXml;
import static com.xenserver.samples.Helpers.probeForFailure;
import static com.xenserver.samples.PoolConnection.connect;

public final class CreateIscsiSr {
    private CreateIscsiSr() {
    }

    /**
     * Create an iSCSI SR.
     *
     * <p>Connect a storage repository to a LUN on an iSCSI target, discovering the target's IQNs and then
     * the LUNs behind one, as the New SR wizard does. Creating the SR formats the LUN, and a shared array
     * offers many targets, so name yours with target_iqn; if the target behind it offers more than one
     * LUN, name yours with scsi_id too.
     *
     * <p>Connect an SR to a LUN on the iSCSI target, discovering the IQN and the LUN the way the New SR
     * wizard does: a device-config that's missing a piece makes the backend fail on purpose, and the
     * failure carries an XML fragment listing what it needs next. SR.create formats the chosen LUN -
     * this is destructive, so pick carefully on a real target: pass targetIqn to name yours (see
     * chooseTargetIqn), and scsiId too if more than one LUN is offered behind it (see chooseLun). Before
     * creating, this probes the chosen LUN itself to make sure it is not already in use by another SR -
     * formatting over one would destroy it.
     *
     * <p>The CHAP password (if any) travels as a Secret, not plaintext device-config, as CreateSmbSr
     * already does for its share password.
     *
     * <p>Run it:
     *
     * <pre>{@code
     * CreateIscsiSr.run("https://xenserver", "root", password, "192.0.2.30", null, null, null, null, null,
     *     "sdk-example-iscsi");
     * }</pre>
     */
    public static void run(String url, String user, String password, String target,
            String port, String chapUser, String chapPassword, String targetIqn, String scsiId,
            String srName) throws Exception {
        final long GiB = 1024L * 1024 * 1024;
        Connection conn = connect(url, user, password);
        Secret secret = null;
        try {
            Host host = Host.getAllRecords(conn).keySet().iterator().next();
            Map<String, String> dc = new java.util.HashMap<>();
            dc.put("target", target);
            if (port != null && !port.isEmpty()) dc.put("port", port);
            if (chapUser != null && !chapUser.isEmpty()) {
                dc.put("chapuser", chapUser);
                Secret.Record secretRec = new Secret.Record();
                secretRec.value = chapPassword;
                secretRec.otherConfig = new java.util.HashMap<>();
                secret = Secret.create(conn, secretRec);
                dc.put("chappassword_secret", secret.getUuid(conn));
            }

            // First failing probe: target only -> the backend lists the IQNs it offers.
            org.w3c.dom.Element iqnRoot = parseXml(probeForFailure(conn, host, dc, "lvmoiscsi")).getDocumentElement();
            dc.put("targetIQN", chooseTargetIqn(iqnRoot, target, targetIqn));
            System.out.println("Discovered IQN: " + dc.get("targetIQN"));

            // Second failing probe: +targetIQN -> the backend lists the LUNs behind it. Real create also
            // carries LUNid whenever it is known.
            org.w3c.dom.Element lunRoot = parseXml(probeForFailure(conn, host, dc, "lvmoiscsi")).getDocumentElement();
            org.w3c.dom.NodeList lunNodes = lunRoot.getElementsByTagName("LUN");
            List<org.w3c.dom.Element> luns = new ArrayList<>();
            for (int i = 0; i < lunNodes.getLength(); i++) luns.add((org.w3c.dom.Element) lunNodes.item(i));
            org.w3c.dom.Element lun = chooseLun(luns, scsiId);
            dc.put("SCSIid", firstTagText(lun, "SCSIid"));
            String lunId = firstTagText(lun, "LUNid");
            dc.put("LUNid", lunId != null ? lunId : String.valueOf(luns.indexOf(lun)));
            System.out.println("Discovered LUN " + dc.get("LUNid") + " (SCSIid " + dc.get("SCSIid") + ")");

            // The device-config is now complete enough to create from - which means it is also complete
            // enough to probe the LUN itself: an <SR> in the answer means one is already there, and
            // SR.create would format it. Reattach that SR rather than destroying it.
            org.w3c.dom.Element srListRoot =
                parseXml(SR.probe(conn, host, dc, "lvmoiscsi", new java.util.HashMap<>())).getDocumentElement();
            org.w3c.dom.NodeList existing = srListRoot.getElementsByTagName("SR");
            if (existing.getLength() > 0) {
                String uuid = firstTagText((org.w3c.dom.Element) existing.item(0), "UUID");
                throw new RuntimeException("LUN " + dc.get("SCSIid") + " already holds SR "
                    + (uuid == null ? "?" : uuid.trim()) + "; creating an SR here would format it - "
                    + "reattach the existing SR instead of creating a new one");
            }

            SR sr = SR.create(conn, host, dc, 0L, srName, "iSCSI SR created by the SDK example",
                "lvmoiscsi", "user", true, new java.util.HashMap<>());
            System.out.println("Created SR: " + sr.getUuid(conn) + " (" + sr.getPhysicalSize(conn) / GiB + " GiB)");
            // Tidy up: this example created the SR, so destroy it - a forgotten SR would stay on the LUN.
            // SR.destroy needs it detached from every host first.
            for (com.xensource.xenapi.PBD pbd : sr.getPBDs(conn))
                if (pbd.getCurrentlyAttached(conn)) pbd.unplug(conn);
            sr.destroy(conn);
        } finally {
            if (secret != null) secret.destroy(conn);
            Session.logout(conn);
        }
        System.out.println("OK: create-iscsi-sr");
    }

    /**
     * Pick the IQN from an iSCSI discovery probe: the caller's, if named (it must be one the target
     * offers), else the first. An array usually offers many targets - one per LUN, often belonging to
     * different users - so on shared storage always name yours: SR.create formats the LUN behind it.
     */
    private static String chooseTargetIqn(org.w3c.dom.Element iqnRoot, String target, String targetIqn) {
        org.w3c.dom.NodeList nodes = iqnRoot.getElementsByTagName("TargetIQN");
        List<String> offered = new ArrayList<>();
        for (int i = 0; i < nodes.getLength(); i++) offered.add(nodes.item(i).getTextContent());
        if (targetIqn == null || targetIqn.isEmpty()) return offered.get(0);
        if (!offered.contains(targetIqn))
            throw new RuntimeException("target " + target + " does not offer IQN " + targetIqn);
        return targetIqn;
    }

    /**
     * Pick the LUN behind the chosen IQN: the caller's SCSIid, if named (it must be one on offer), else
     * the one LUN, if that target offers only one. The New SR wizard auto-selects a LUN only when exactly
     * one is on offer, and otherwise makes the caller choose - picking blindly on a shared target risks
     * formatting someone else's disk.
     */
    private static org.w3c.dom.Element chooseLun(List<org.w3c.dom.Element> luns, String scsiId) {
        if (scsiId != null && !scsiId.isEmpty()) {
            for (org.w3c.dom.Element lun : luns) {
                if (scsiId.equals(firstTagText(lun, "SCSIid"))) return lun;
            }
            StringJoiner offered = new StringJoiner(", ");
            for (org.w3c.dom.Element lun : luns) offered.add(firstTagText(lun, "SCSIid"));
            throw new RuntimeException("target does not offer a LUN with SCSIid " + scsiId + "; offered: " + offered);
        }
        if (luns.size() == 1) return luns.get(0);
        StringJoiner offered = new StringJoiner(", ");
        for (org.w3c.dom.Element lun : luns) {
            offered.add(firstTagText(lun, "SCSIid") + " (" + firstTagText(lun, "size") + " bytes)");
        }
        throw new RuntimeException("target offers " + luns.size() + " LUNs; name one with scsiId: " + offered);
    }
}
```

<details><summary>Example output</summary>

```text
Discovered IQN: iqn.2009-01.com.example:target-0
Discovered LUN 0 (SCSIid 360a980004265656d5f4a2d63764e5734)
Created SR: 00000001-0000-0000-080b-000000000000 (200 GiB)
OK: create-iscsi-sr
```

</details>

## Go

Source: [`go/create_iscsi_sr.go`](../../go/create_iscsi_sr.go)

```go
package main

import (
	"encoding/xml"
	"fmt"
	"strings"

	"go/xenapi"
)

// createIscsiSr - Create an iSCSI SR.
//
// Connect a storage repository to a LUN on an iSCSI target, discovering the target's IQNs and then
// the LUNs behind one, as the New SR wizard does. Creating the SR formats the LUN, and a shared
// array offers many targets, so name yours with target_iqn; if the target behind it offers more
// than one LUN, name yours with scsi_id too.
//
// Connect an SR to a LUN on the iSCSI target, discovering the IQN and the LUN the way the New SR
// wizard does: a device-config that's missing a piece makes the backend fail on purpose, and the
// failure carries an XML fragment listing what it needs next.
//
// SR.create formats the chosen LUN - this is destructive, so pick carefully on a real target: pass
// targetIQN to name yours (see chooseTargetIQN), and scsiID too if more than one LUN is offered
// behind it (see chooseLUN). Before creating, this probes the chosen LUN itself to make sure it is
// not already in use by another SR - formatting over one would destroy it.
//
// The CHAP password (if any) travels as a Secret, not plaintext device-config, as createSmbSr
// already does for its share password.
func createIscsiSr(url, user, password, target, port, chapUser, chapPassword, targetIQN, scsiID, srName string) {
	const GiB = 1024 * 1024 * 1024
	session := connect(url, user, password)
	hosts, err := xenapi.Host.GetAll(session)
	check(err)
	host := hosts[0]
	dc := map[string]string{"target": target}
	if port != "" {
		dc["port"] = port
	}
	var secret xenapi.SecretRef
	secretDestroyed := true
	if chapUser != "" {
		dc["chapuser"] = chapUser
		secret, err = xenapi.Secret.Create(session, xenapi.SecretRecord{
			Value: chapPassword, OtherConfig: map[string]string{},
		})
		check(err)
		secretUUID, err := xenapi.Secret.GetUUID(session, secret)
		check(err)
		dc["chappassword_secret"] = secretUUID
		secretDestroyed = false
	}
	// Whatever happens next, destroy the secret: a failure part-way would otherwise leak it. (Logging
	// out first would make this deferred cleanup fail SESSION_INVALID, so the success path destroys
	// the secret itself, below, before logging out.)
	defer func() {
		if !secretDestroyed {
			xenapi.Secret.Destroy(session, secret)
		}
	}()

	// First failing probe: target only -> the backend lists the IQNs it offers.
	dc["targetIQN"] = chooseTargetIQN(probeForFailure(session, host, dc, "lvmoiscsi"), target, targetIQN)
	fmt.Printf("Discovered IQN: %s\n", dc["targetIQN"])

	// Second failing probe: +targetIQN -> the backend lists the LUNs behind it. Real create also
	// carries LUNid whenever it is known; fall back to the first LUN's list index (0) if the
	// backend doesn't report one.
	luns := findXMLElements(probeForFailure(session, host, dc, "lvmoiscsi"), "LUN")
	lun := chooseLUN(luns, scsiID)
	dc["SCSIid"] = lun["SCSIid"]
	if id := lun["LUNid"]; id != "" {
		dc["LUNid"] = id
	} else {
		dc["LUNid"] = "0"
	}
	fmt.Printf("Discovered LUN %s (SCSIid %s)\n", dc["LUNid"], dc["SCSIid"])

	// The device-config is now complete enough to create from - which means it is also complete
	// enough to probe the LUN itself: an <SR> in the answer means one is already there, and
	// SR.create would format it. Reattach that SR rather than destroying it.
	srProbe, err := xenapi.SR.Probe(session, host, dc, "lvmoiscsi", map[string]string{})
	check(err)
	if existing := findXMLElements(srProbe, "SR"); len(existing) > 0 {
		panic(fmt.Sprintf("LUN %s already holds SR %s; creating an SR here would format it - "+
			"reattach the existing SR instead of creating a new one",
			dc["SCSIid"], strings.TrimSpace(existing[0]["UUID"])))
	}

	sr, err := xenapi.SR.Create(session, host, dc, 0, srName,
		"iSCSI SR created by the SDK example", "lvmoiscsi", "user", true, map[string]string{})
	check(err)
	size, _ := xenapi.SR.GetPhysicalSize(session, sr)
	uuid, _ := xenapi.SR.GetUUID(session, sr)
	fmt.Printf("Created SR: %s (%d GiB)\n", uuid, size/GiB)
	// Tidy up: this example created the SR, so destroy it - a forgotten SR would stay on the LUN.
	// SR.destroy needs it detached from every host first.
	pbds, err := xenapi.SR.GetPBDs(session, sr)
	check(err)
	for _, pbd := range pbds {
		if attached, _ := xenapi.PBD.GetCurrentlyAttached(session, pbd); attached {
			check(xenapi.PBD.Unplug(session, pbd))
		}
	}
	check(xenapi.SR.Destroy(session, sr))
	if !secretDestroyed {
		check(xenapi.Secret.Destroy(session, secret))
		secretDestroyed = true
	}
	fmt.Println("OK: create-iscsi-sr")
	session.Logout()
}

// findXMLElements scans an XML document for every element named tag, at any depth (the root
// element name and nesting both vary by host/backend - the probe helpers below must not assume
// either), and returns a map of each one's immediate child elements' tag name to text content.
func findXMLElements(xmlText, tag string) []map[string]string {
	var elements []map[string]string
	decoder := xml.NewDecoder(strings.NewReader(xmlText))
	for {
		tok, err := decoder.Token()
		if err != nil {
			break
		}
		start, ok := tok.(xml.StartElement)
		if !ok || start.Name.Local != tag {
			continue
		}
		var raw struct {
			Fields []struct {
				XMLName xml.Name
				Value   string `xml:",chardata"`
			} `xml:",any"`
		}
		check(decoder.DecodeElement(&raw, &start))
		fields := map[string]string{}
		for _, f := range raw.Fields {
			fields[f.XMLName.Local] = f.Value
		}
		elements = append(elements, fields)
	}
	return elements
}

// chooseTargetIQN picks the IQN from an iSCSI discovery probe's XML: the caller's, if named (it must
// be one the target offers), else the first. An array usually offers many targets - one per LUN,
// often belonging to different users - so on shared storage always name yours: SR.create formats
// the LUN behind it.
func chooseTargetIQN(xmlText, target, targetIQN string) string {
	var offered []string
	decoder := xml.NewDecoder(strings.NewReader(xmlText))
	for {
		tok, err := decoder.Token()
		if err != nil {
			break
		}
		if start, ok := tok.(xml.StartElement); ok && start.Name.Local == "TargetIQN" {
			var iqn string
			check(decoder.DecodeElement(&iqn, &start))
			offered = append(offered, strings.TrimSpace(iqn))
		}
	}
	if len(offered) == 0 {
		panic(fmt.Sprintf("target %s offered no IQNs: %s", target, xmlText))
	}
	if targetIQN == "" {
		return offered[0]
	}
	for _, iqn := range offered {
		if iqn == targetIQN {
			return iqn
		}
	}
	panic(fmt.Sprintf("target %s does not offer IQN %s", target, targetIQN))
}

// chooseLUN picks the LUN behind the chosen IQN: the caller's SCSIid, if named (it must be one on
// offer), else the one LUN, if that target offers only one. The New SR wizard auto-selects a LUN
// only when exactly one is on offer, and otherwise makes the caller choose - picking blindly on a
// shared target risks formatting someone else's disk.
func chooseLUN(luns []map[string]string, scsiID string) map[string]string {
	if scsiID != "" {
		for _, lun := range luns {
			if lun["SCSIid"] == scsiID {
				return lun
			}
		}
		var offered []string
		for _, lun := range luns {
			offered = append(offered, lun["SCSIid"])
		}
		panic(fmt.Sprintf("target does not offer a LUN with SCSIid %s; offered: %s",
			scsiID, strings.Join(offered, ", ")))
	}
	if len(luns) == 1 {
		return luns[0]
	}
	var offered []string
	for _, lun := range luns {
		offered = append(offered, fmt.Sprintf("%s (%s bytes)", lun["SCSIid"], lun["size"]))
	}
	panic(fmt.Sprintf("target offers %d LUNs; name one with scsiID: %s", len(luns), strings.Join(offered, ", ")))
}
```

<details><summary>Example output</summary>

```text
Discovered IQN: iqn.2009-01.com.example:target-0
Discovered LUN 0 (SCSIid 360a980004265656d5f4a2d63764e5734)
Created SR: 00000001-0000-0000-6c0a-000000000000 (200 GiB)
OK: create-iscsi-sr
```

</details>

## PowerShell

Source: [`powershell/Storage/Invoke-CreateIscsiSr.ps1`](../../powershell/Storage/Invoke-CreateIscsiSr.ps1)

```powershell
function Invoke-CreateIscsiSr {
    <#
    .SYNOPSIS
        Create an iSCSI SR.
    .DESCRIPTION
        Connect a storage repository to a LUN on an iSCSI target, discovering the target's IQNs and then the
        LUNs behind one, as the New SR wizard does. Creating the SR formats the LUN, and a shared array
        offers many targets, so name yours with target_iqn; if the target behind it offers more than one
        LUN, name yours with ScsiId too.
    .EXAMPLE
        Invoke-CreateIscsiSr -Url https://xenserver -UserName root -Password $password
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password,
        [Parameter(Mandatory = $true)][string]$Target,
        [string]$Port,
        [string]$ChapUser,
        [string]$ChapPassword,
        [string]$TargetIqn,
        [string]$ScsiId,
        [string]$SrName = "sdk-example-iscsi"
    )
    # Connect an SR to a LUN on the iSCSI target, discovering the IQN and the LUN the way the New SR
    # wizard does: a device-config that's missing a piece makes the backend fail on purpose, and the
    # failure carries an XML fragment listing what it needs next.
    #
    # SR.create formats the chosen LUN - this is destructive, so pick carefully on a real target: pass
    # TargetIqn to name yours (see Select-TargetIqn), and ScsiId too if more than one LUN is offered
    # behind it (see Select-Lun). Before creating, this probes the chosen LUN itself to make sure it is
    # not already in use by another SR - formatting over one would destroy it.
    #
    # The CHAP password (if any) travels as a Secret, not plaintext device-config, as Invoke-CreateSmbSr
    # already does for its share password.
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password
    $xenHost = Get-XenHost | Select-Object -First 1
    $dc = @{ target = $Target }
    if ($Port) { $dc["port"] = $Port }
    $secret = $null
    if ($ChapUser) {
        $dc["chapuser"] = $ChapUser
        $secret = New-XenSecret -Value $ChapPassword -OtherConfig @{} -PassThru
        $dc["chappassword_secret"] = $secret.uuid
    }

    try {
        # First failing probe: target only -> the backend lists the IQNs it offers.
        $iqnXml = [xml](Invoke-ProbeForFailure -XenHostRef $xenHost.opaque_ref -DeviceConfig $dc -SmType lvmoiscsi)
        $dc["targetIQN"] = Select-TargetIqn -IqnXml $iqnXml -Target $Target -TargetIqn $TargetIqn
        Write-Host "Discovered IQN: $($dc['targetIQN'])"

        # Second failing probe: +targetIQN -> the backend lists the LUNs behind it. Real create also
        # carries LUNid whenever it is known.
        $lunXml = [xml](Invoke-ProbeForFailure -XenHostRef $xenHost.opaque_ref -DeviceConfig $dc -SmType lvmoiscsi)
        $luns = @($lunXml.SelectNodes("//LUN"))
        $lun = Select-Lun -Luns $luns -ScsiId $ScsiId
        $dc["SCSIid"] = $lun.SCSIid
        $lunIdNode = $lun.SelectSingleNode("LUNid")
        $dc["LUNid"] = if ($lunIdNode) { $lunIdNode.InnerText } else { [string]([array]::IndexOf($luns, $lun)) }
        Write-Host "Discovered LUN $($dc['LUNid']) (SCSIid $($dc['SCSIid']))"

        # The device-config is now complete enough to create from - which means it is also complete
        # enough to probe the LUN itself: an <SR> in the answer means one is already there, and
        # SR.create would format it. Reattach that SR rather than destroying it.
        $probe = Invoke-XenSR -Ref "OpaqueRef:NULL" -XenAction Probe -XenHost $xenHost.opaque_ref -DeviceConfig $dc `
            -Type lvmoiscsi -SmConfig @{} -PassThru
        $existing = @(([xml]$probe).SelectNodes('/SRlist/SR'))
        if ($existing.Count -gt 0) {
            throw "LUN $($dc['SCSIid']) already holds SR $("$($existing[0].UUID)".Trim()); creating an SR " +
                "here would format it - reattach the existing SR instead of creating a new one"
        }

        $sr = New-XenSR -XenHost $xenHost -DeviceConfig $dc -PhysicalSize 0 `
            -NameLabel $SrName -NameDescription "iSCSI SR created by the SDK example" `
            -Type "lvmoiscsi" -ContentType "user" -Shared $true -PassThru
        Write-Host "Created SR: $($sr.uuid) ($([math]::Floor([long]($sr.physical_size) / 1GB)) GiB)"
        # Tidy up: this example created the SR, so destroy it - a forgotten SR would stay on the LUN.
        # SR.destroy needs it detached from every host first.
        Get-XenPBD | Where-Object { $_.SR.opaque_ref -eq $sr.opaque_ref -and $_.currently_attached } |
            ForEach-Object { $_ | Invoke-XenPBD -XenAction Unplug }
        Remove-XenSR -Ref $sr.opaque_ref
    }
    finally {
        if ($secret) { Remove-XenSecret -Ref $secret.opaque_ref }
    }
    Write-Host "OK: create-iscsi-sr"
    $session | Disconnect-XenServer
}

function Select-TargetIqn {
    <#
    .SYNOPSIS
        Pick the IQN from an iSCSI discovery probe.
    .DESCRIPTION
        The caller's, if named (it must be one the target offers), else the first. An array usually offers
        many targets - one per LUN, often belonging to different users - so on shared storage always name
        yours: SR.create formats the LUN behind it.
    #>
    param(
        [Parameter(Mandatory = $true)][xml]$IqnXml,
        [Parameter(Mandatory = $true)][string]$Target,
        [string]$TargetIqn
    )
    $offered = @($IqnXml.SelectNodes("//TargetIQN") | ForEach-Object { $_.InnerText })
    if (-not $TargetIqn) { return $offered[0] }
    if ($offered -notcontains $TargetIqn) { throw "target $Target does not offer IQN $TargetIqn" }
    return $TargetIqn
}

function Select-Lun {
    <#
    .SYNOPSIS
        Pick the LUN behind the chosen IQN.
    .DESCRIPTION
        The caller's SCSIid, if named (it must be one on offer), else the one LUN, if that target offers
        only one. The New SR wizard auto-selects a LUN only when exactly one is on offer, and otherwise
        makes the caller choose - picking blindly on a shared target risks formatting someone else's disk.
    #>
    param(
        [Parameter(Mandatory = $true)][array]$Luns,
        [string]$ScsiId
    )
    if ($ScsiId) {
        $lun = $Luns | Where-Object { $_.SCSIid -eq $ScsiId } | Select-Object -First 1
        if (-not $lun) {
            $offered = ($Luns | ForEach-Object { $_.SCSIid }) -join ", "
            throw "target does not offer a LUN with SCSIid $ScsiId; offered: $offered"
        }
        return $lun
    }
    if ($Luns.Count -eq 1) { return $Luns[0] }
    $offered = ($Luns | ForEach-Object { "$($_.SCSIid) ($($_.size) bytes)" }) -join ", "
    throw "target offers $($Luns.Count) LUNs; name one with ScsiId: $offered"
}
```

<details><summary>Example output</summary>

```text
Discovered IQN: iqn.2009-01.com.example:target-0
Discovered LUN 0 (SCSIid 360a980004265656d5f4a2d63764e5734)
Created SR: 00000001-0000-0000-db0a-000000000000 (200 GiB)
OK: create-iscsi-sr
```

</details>

## xe CLI

Source: [`cli/storage/create-iscsi-sr.sh`](../../cli/storage/create-iscsi-sr.sh)

```bash
# Create an iSCSI SR.
#
# Connect a storage repository to a LUN on an iSCSI target, discovering the target's IQNs and then the LUNs
# behind one, as the New SR wizard does. Creating the SR formats the LUN, and a shared array offers many
# targets, so name yours with target_iqn; if the target behind it offers more than one LUN, name yours with
# scsi_id too.
#
# Run it:
#   ./workflows.sh create-iscsi-sr https://xenserver root "$password"
#
# Optional key=value arguments (default):
#   target (192.0.2.30)
#   target_iqn ("")
#   scsi_id (360a980004265656d5f4a2d63764e5734)
#   port ("")
#   chap_user ("")
#   chap_password ("")
#   sr_name (xe-example-iscsi)

# Discover the IQN and the LUN the way the New SR wizard does, instead of a hard-coded target: a
# device-config that's missing a piece makes the backend fail on purpose, and the failure carries an XML
# fragment listing what it needs next. sr-create formats the chosen LUN - this is destructive, so pick
# carefully on a real target: pass target_iqn to name yours (see choose_target_iqn), and scsi_id too if
# more than one LUN is offered behind it (see choose_lun). Before creating, this probes the chosen LUN
# itself to make sure it is not already in use by another SR - formatting over one would destroy it.
#
# The CHAP password (if any) travels as a Secret, not plaintext device-config, as create_smb_sr already
# does for its share password.
create_iscsi_sr() {
    local target target_iqn scsi_wanted port chap_user chap_password sr_name h xml
    local scsi_id lun lun_id existing_xml uuid
    local -a dc
    target=$(param target "192.0.2.30")
    target_iqn=$(param target_iqn "")
    scsi_wanted=$(param scsi_id "360a980004265656d5f4a2d63764e5734")
    port=$(param port "")
    chap_user=$(param chap_user "")
    chap_password=$(param chap_password "")
    sr_name=$(param sr_name "xe-example-iscsi")
    h=$(first_host)

    dc=(device-config:target="$target")
    [ -n "$port" ] && dc+=(device-config:port="$port")
    # secret (not local: the EXIT trap below reads it after this function has returned).
    secret=""
    if [ -n "$chap_user" ]; then
        secret=$(xe secret-create value="$chap_password")
        trap 'xe secret-destroy uuid=$secret >/dev/null 2>&1' EXIT
        dc+=(device-config:chapuser="$chap_user" device-config:chappassword_secret="$secret")
    fi

    # First failing probe: target only -> the backend lists the IQNs it offers.
    xml=$(probe_for_failure lvmoiscsi host-uuid="$h" "${dc[@]}")
    target_iqn=$(choose_target_iqn "$xml" "$target" "$target_iqn")
    echo "Discovered IQN: $target_iqn"
    dc+=(device-config:targetIQN="$target_iqn")

    # Second failing probe: +targetIQN -> the backend lists the LUNs behind it.
    xml=$(probe_for_failure lvmoiscsi host-uuid="$h" "${dc[@]}")
    lun=$(choose_lun "$xml" "$scsi_wanted")
    scsi_id=$(xml_tag_text "$lun" SCSIid)
    lun_id=$(xml_tag_text "$lun" LUNid); lun_id=${lun_id:-0}
    echo "Discovered LUN $lun_id (SCSIid $scsi_id)"
    dc+=(device-config:SCSIid="$scsi_id" device-config:LUNid="$lun_id")

    # The device-config is now complete enough to create from - which means it is also complete enough to
    # probe the LUN itself: an <SR> in the answer means one is already there, and sr-create would format
    # it. Reattach that SR rather than destroying it.
    existing_xml=$(xe sr-probe type=lvmoiscsi "${dc[@]}")
    if uuid=$(xml_tag_text "$existing_xml" UUID); then
        echo "LUN $scsi_id already holds SR $uuid; creating an SR here would format it - reattach the" \
             "existing SR instead of creating a new one" >&2
        return 1
    fi

    sr=$(xe sr-create host-uuid="$h" type=lvmoiscsi name-label="$sr_name" shared=true "${dc[@]}")
    echo "Created iSCSI SR: $sr ($(( $(xe sr-param-get uuid=$sr param-name=physical-size) / 1024 / 1024 / 1024 )) GiB)"
    # Tidy up: this example created the SR, so destroy it - a forgotten SR would stay on the LUN.
    # SR.destroy needs it detached from every host first.
    for pbd in $(each_csv "$(xe pbd-list sr-uuid=$sr currently-attached=true --minimal)"); do
        xe pbd-unplug uuid=$pbd
    done
    xe sr-destroy uuid=$sr
    if [ -n "$secret" ]; then
        xe secret-destroy uuid=$secret
        trap - EXIT
        secret=""
    fi
    echo "OK: create-iscsi-sr"
}

# Pick the IQN from an iSCSI discovery probe's XML: the caller's, if named (it must be one the target
# offers), else the first. An array usually offers many targets - one per LUN, often belonging to different
# users - so on shared storage always name yours: sr-create formats the LUN behind it.
choose_target_iqn() {
    local rest=$1 target=$2 wanted=$3 first="" iqn
    while [[ $rest == *"<TargetIQN>"* ]]; do
        rest=${rest#*<TargetIQN>}; iqn=${rest%%</TargetIQN>*}
        [ -n "$first" ] || first=$iqn
        if [ -n "$wanted" ] && [ "$iqn" = "$wanted" ]; then echo "$iqn"; return 0; fi
    done
    if [ -n "$wanted" ]; then echo "target $target does not offer IQN $wanted" >&2; return 1; fi
    echo "$first"
}

# Pick the LUN behind the chosen IQN: the caller's SCSIid, if named (it must be one on offer), else the one
# LUN, if that target offers only one. The New SR wizard auto-selects a LUN only when exactly one is on
# offer, and otherwise makes the caller choose - picking blindly on a shared target risks formatting
# someone else's disk. Echoes the chosen <LUN>...</LUN> fragment.
choose_lun() {
    local xml=$1 wanted=$2 rest=$xml block scsi_id
    local -a blocks=()
    while [[ $rest == *"<LUN>"* ]]; do
        block=${rest#*<LUN>}; rest=${block#*</LUN>}; block="<LUN>${block%%</LUN>*}"
        blocks+=("$block")
    done
    if [ -n "$wanted" ]; then
        for block in "${blocks[@]}"; do
            scsi_id=$(xml_tag_text "$block" SCSIid)
            if [ "$scsi_id" = "$wanted" ]; then echo "$block"; return 0; fi
        done
        local offered="" sep=""
        for block in "${blocks[@]}"; do offered+="$sep$(xml_tag_text "$block" SCSIid)"; sep=", "; done
        echo "target does not offer a LUN with SCSIid $wanted; offered: $offered" >&2
        return 1
    fi
    if [ "${#blocks[@]}" -eq 1 ]; then echo "${blocks[0]}"; return 0; fi
    local offered="" sep=""
    for block in "${blocks[@]}"; do
        offered+="$sep$(xml_tag_text "$block" SCSIid) ($(xml_tag_text "$block" size) bytes)"; sep=", "
    done
    echo "target offers ${#blocks[@]} LUNs; name one with scsi_id: $offered" >&2
    return 1
}
```

<details><summary>Example output</summary>

```text
Discovered IQN: iqn.2009-01.com.example:target-0
Discovered LUN 0 (SCSIid 360a980004265656d5f4a2d63764e5734)
Created iSCSI SR: 00000001-0000-0000-b60a-000000000000 (200 GiB)
OK: create-iscsi-sr
```

</details>
