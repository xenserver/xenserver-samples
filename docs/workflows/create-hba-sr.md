<!-- Generated from workflows.json, the example sources and a run of each example. Edit those, not this file. -->

# Create an HBA SR

Connect a shared storage repository to a fibre-channel (HBA) LUN: discover the LUNs the host can see with a deliberately failing probe, then create the SR by SCSI ID. Creating the SR formats the LUN.

**Requires:** a Fibre Channel or SAS LUN.

**Caution:** formats the LUN it uses (name it with scsi_id; it refuses a LUN that already holds an SR) and destroys the new SR again afterwards.

Workflow `create-hba-sr`. [All workflows](README.md) · [Connecting](connecting.md)

## C# (.NET)

Source: [`csharp/Storage/CreateHbaSr.cs`](../../csharp/Storage/CreateHbaSr.cs)

```csharp
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
```

<details><summary>Sample output</summary>

```text
Discovered LUN: SCSIid 360a980004265656d5f4a2d63764e5736 on /dev/sdb [sdc]
Created SR: 00000001-0000-0000-770a-000000000000 (512 GiB)
OK: create-hba-sr
```

</details>

## Python

Source: [`python/storage/create_hba_sr.py`](../../python/storage/create_hba_sr.py)

```python
"""Create an HBA SR.

Connect a shared storage repository to a fibre-channel (HBA) LUN: discover the LUNs the host can see
with a deliberately failing probe, then create the SR by SCSI ID. Creating the SR formats the LUN.
"""

import xml.etree.ElementTree as ET

from connection import connect
from helpers import probe_for_failure


def create_hba_sr(url, username, password, scsi_id="", sr_name="sdk-example-hba"):
    """Connect a shared SR to a fibre-channel (HBA) LUN, discovering it the way the New SR wizard
    does: probing with no SCSIid fails on purpose and lists every LUN the backend can see.

    SR.create formats the chosen LUN - this is destructive. On shared FC storage a host sees LUNs
    other hosts are using, so name the one that is yours (scsi_id); with none, the first LUN listed
    is taken, which is only right on a dedicated test target."""
    GIB = 1024 * 1024 * 1024
    session = connect(url, username, password)
    host = session.xenapi.host.get_all()[0]

    # The root element varies by backend; find BlockDevice entries by tag wherever they are.
    devlist_xml = ET.fromstring(probe_for_failure(session, host, {}, "lvmohba"))
    device = next((d for d in devlist_xml.iter("BlockDevice")
                   if not scsi_id or d.find("SCSIid").text == scsi_id), None)
    if device is None:
        raise RuntimeError("no LUN with SCSIid %s is visible to this host" % scsi_id)
    scsi_id = device.find("SCSIid").text
    path = device.find("path").text
    print("Discovered LUN: SCSIid %s on %s" % (scsi_id, path))

    # SCSIid is all lvmohba needs. (The probe's <path> is for display: on a real host it reads
    # like "/dev/sde [sdc] [sdg] [sdi]", one entry per path.)
    dc = {"SCSIid": scsi_id}

    # SCSIid alone is also enough to probe the LUN itself: an <SR> in the answer means one is already
    # there, and SR.create would format it. Reattach that SR rather than destroying it.
    srlist_xml = ET.fromstring(session.xenapi.SR.probe(host, dc, "lvmohba", {}))
    existing = srlist_xml.find("SR")
    if existing is not None:
        raise RuntimeError("LUN %s already holds SR %s; creating an SR here would format it - "
                            "reattach the existing SR instead of creating a new one"
                            % (scsi_id, existing.find("UUID").text.strip()))

    sr = session.xenapi.SR.create(host, dc, "0", sr_name,
                                  "HBA SR created by the SDK example", "lvmohba", "user", True, {})
    print("Created SR: %s (%d GiB)"
          % (session.xenapi.SR.get_uuid(sr), int(session.xenapi.SR.get_physical_size(sr)) // GIB))
    # Tidy up: this example created the SR, so destroy it - a forgotten SR would stay on the LUN.
    # SR.destroy needs it detached from every host first.
    for pbd in session.xenapi.SR.get_PBDs(sr):
        if session.xenapi.PBD.get_currently_attached(pbd):
            session.xenapi.PBD.unplug(pbd)
    session.xenapi.SR.destroy(sr)
    print("OK: create-hba-sr")
    session.logout()
```

<details><summary>Sample output</summary>

```text
Discovered LUN: SCSIid 360a980004265656d5f4a2d63764e5736 on /dev/sdb [sdc]
Created SR: 00000001-0000-0000-f20a-000000000000 (512 GiB)
OK: create-hba-sr
```

</details>

## Java

Source: [`java/src/main/java/com/xenserver/samples/storage/CreateHbaSr.java`](../../java/src/main/java/com/xenserver/samples/storage/CreateHbaSr.java)

```java
package com.xenserver.samples.storage;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.Host;
import com.xensource.xenapi.SR;
import com.xensource.xenapi.Session;

import java.util.Map;

import static com.xenserver.samples.Helpers.firstTagText;
import static com.xenserver.samples.Helpers.parseXml;
import static com.xenserver.samples.Helpers.probeForFailure;
import static com.xenserver.samples.PoolConnection.connect;

public final class CreateHbaSr {
    private CreateHbaSr() {
    }

    /**
     * Create an HBA SR.
     *
     * <p>Connect a shared storage repository to a fibre-channel (HBA) LUN: discover the LUNs the host can
     * see with a deliberately failing probe, then create the SR by SCSI ID. Creating the SR formats the
     * LUN.
     *
     * <p>Connect a shared SR to a fibre-channel (HBA) LUN, discovering it the way the New SR wizard does:
     * probing with no SCSIid fails on purpose and lists every LUN the backend can see. SR.create formats
     * the chosen LUN - this is destructive, so pick carefully on a real target.
     *
     * <p>Run it:
     *
     * <pre>{@code
     * CreateHbaSr.run("https://xenserver", "root", password, "<SCSIid of your LUN>", "sdk-example-hba");
     * }</pre>
     */
    public static void run(String url, String user, String password, String scsiId, String srName)
            throws Exception {
        final long GiB = 1024L * 1024 * 1024;
        Connection conn = connect(url, user, password);
        try {
            Host host = Host.getAllRecords(conn).keySet().iterator().next();

            // The root element varies by backend; find BlockDevice entries by tag wherever they are.
            org.w3c.dom.Element devlistRoot =
                parseXml(probeForFailure(conn, host, new java.util.HashMap<>(), "lvmohba")).getDocumentElement();
            // SR.create formats the LUN: on shared FC storage name yours (scsiId); with none, the first is taken.
            org.w3c.dom.NodeList devices = devlistRoot.getElementsByTagName("BlockDevice");
            org.w3c.dom.Element device = null;
            for (int i = 0; i < devices.getLength() && device == null; i++) {
                org.w3c.dom.Element d = (org.w3c.dom.Element) devices.item(i);
                if (scsiId.isEmpty() || firstTagText(d, "SCSIid").equals(scsiId)) device = d;
            }
            if (device == null) throw new RuntimeException("no LUN with SCSIid " + scsiId + " is visible to this host");
            scsiId = firstTagText(device, "SCSIid");
            String path = firstTagText(device, "path");
            System.out.println("Discovered LUN: SCSIid " + scsiId + " on " + path);

            // SCSIid is all lvmohba needs. (The probe's <path> is for display: on a real host it reads like
            // "/dev/sde [sdc] [sdg] [sdi]", one entry per path.)
            Map<String, String> dc = new java.util.HashMap<>();
            dc.put("SCSIid", scsiId);

            // SCSIid alone is also enough to probe the LUN itself: an <SR> in the answer means one is
            // already there, and SR.create would format it. Reattach that SR rather than
            // destroying it.
            org.w3c.dom.Element srListRoot =
                parseXml(SR.probe(conn, host, dc, "lvmohba", new java.util.HashMap<>())).getDocumentElement();
            org.w3c.dom.NodeList existing = srListRoot.getElementsByTagName("SR");
            if (existing.getLength() > 0) {
                String uuid = firstTagText((org.w3c.dom.Element) existing.item(0), "UUID");
                throw new RuntimeException("LUN " + scsiId + " already holds SR "
                    + (uuid == null ? "?" : uuid.trim()) + "; creating an SR here would format it - "
                    + "reattach the existing SR instead of creating a new one");
            }

            SR sr = SR.create(conn, host, dc, 0L, srName, "HBA SR created by the SDK example",
                "lvmohba", "user", true, new java.util.HashMap<>());
            System.out.println("Created SR: " + sr.getUuid(conn) + " (" + sr.getPhysicalSize(conn) / GiB + " GiB)");
            // Tidy up: this example created the SR, so destroy it - a forgotten SR would stay on the LUN.
            // SR.destroy needs it detached from every host first.
            for (com.xensource.xenapi.PBD pbd : sr.getPBDs(conn))
                if (pbd.getCurrentlyAttached(conn)) pbd.unplug(conn);
            sr.destroy(conn);
            System.out.println("OK: create-hba-sr");
        } finally {
            Session.logout(conn);
        }
    }
}
```

<details><summary>Sample output</summary>

```text
Discovered LUN: SCSIid 360a980004265656d5f4a2d63764e5736 on /dev/sdb [sdc]
Created SR: 00000001-0000-0000-9d0a-000000000000 (512 GiB)
OK: create-hba-sr
```

</details>

## Go

Source: [`go/create_hba_sr.go`](../../go/create_hba_sr.go)

```go
package main

import (
	"fmt"
	"strings"

	"go/xenapi"
)

// createHbaSr - Create an HBA SR.
//
// Connect a shared storage repository to a fibre-channel (HBA) LUN: discover the LUNs the host can
// see with a deliberately failing probe, then create the SR by SCSI ID. Creating the SR formats the
// LUN.
//
// Connect a shared SR to a fibre-channel (HBA) LUN, discovering it the way the New SR wizard does:
// probing with no SCSIid fails on purpose and lists every LUN the backend can see. The failure's
// XML root element name and error code both vary between XenServer versions, so parse by tag name
// BlockDevice wherever it occurs.
//
// SR.create formats the chosen LUN - this is destructive, so pick carefully on a real target.
func createHbaSr(url, user, password, scsiID, srName string) {
	const GiB = 1024 * 1024 * 1024
	session := connect(url, user, password)
	hosts, err := xenapi.Host.GetAll(session)
	check(err)
	host := hosts[0]

	// SR.create formats the LUN: on shared FC storage name yours (scsiID); with none, the first is taken.
	device := findXMLElement(probeForFailure(session, host, map[string]string{}, "lvmohba"), "BlockDevice",
		"SCSIid", scsiID)
	fmt.Printf("Discovered LUN: SCSIid %s on %s\n", device["SCSIid"], device["path"])

	// SCSIid is all lvmohba needs. (The probe's <path> is for display: on a real host it reads
	// like "/dev/sde [sdc] [sdg] [sdi]", one entry per path.)
	dc := map[string]string{"SCSIid": device["SCSIid"]}

	// SCSIid alone is also enough to probe the LUN itself: an <SR> in the answer means one is already
	// there, and SR.create would format it. Reattach that SR rather than destroying it.
	srProbe, err := xenapi.SR.Probe(session, host, dc, "lvmohba", map[string]string{})
	check(err)
	if existing := findXMLElements(srProbe, "SR"); len(existing) > 0 {
		panic(fmt.Sprintf("LUN %s already holds SR %s; creating an SR here would format it - "+
			"reattach the existing SR instead of creating a new one",
			device["SCSIid"], strings.TrimSpace(existing[0]["UUID"])))
	}

	sr, err := xenapi.SR.Create(session, host, dc, 0, srName,
		"HBA SR created by the SDK example", "lvmohba", "user", true, map[string]string{})
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
	fmt.Println("OK: create-hba-sr")
	session.Logout()
}
```

<details><summary>Sample output</summary>

```text
Discovered LUN: SCSIid 360a980004265656d5f4a2d63764e5736 on /dev/sdb [sdc]
Created SR: 00000001-0000-0000-f50a-000000000000 (512 GiB)
OK: create-hba-sr
```

</details>

## PowerShell

Source: [`powershell/Storage/Invoke-CreateHbaSr.ps1`](../../powershell/Storage/Invoke-CreateHbaSr.ps1)

```powershell
function Invoke-CreateHbaSr {
    <#
    .SYNOPSIS
        Create an HBA SR.
    .DESCRIPTION
        Connect a shared storage repository to a fibre-channel (HBA) LUN: discover the LUNs the host can see
        with a deliberately failing probe, then create the SR by SCSI ID. Creating the SR formats the LUN.
    .EXAMPLE
        Invoke-CreateHbaSr -Url https://xenserver -UserName root -Password $password
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password,
        [string]$ScsiId = "",
        [string]$SrName = "sdk-example-hba"
    )
    # Connect a shared SR to a fibre-channel (HBA) LUN, discovering it the way the New SR wizard does:
    # probing with no SCSIid fails on purpose and lists every LUN the backend can see.
    #
    # SR.create formats the chosen LUN - this is destructive. On shared FC storage a host sees LUNs other
    # hosts are using, so name the one that is yours (-ScsiId); with none, the first LUN listed is taken,
    # which is only right on a dedicated test target.
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password
    $xenHost = Get-XenHost | Select-Object -First 1

    # The root element varies by backend; find BlockDevice entries by tag wherever they are.
    $devlistXml = [xml](Invoke-ProbeForFailure -XenHostRef $xenHost.opaque_ref -DeviceConfig @{} -SmType lvmohba)
    $device = $devlistXml.SelectNodes("//BlockDevice") |
        Where-Object { -not $ScsiId -or $_.SCSIid -eq $ScsiId } | Select-Object -First 1
    if (-not $device) { throw "no LUN with SCSIid $ScsiId is visible to this host" }
    $scsiId = $device.SCSIid
    $path = $device.path
    Write-Host "Discovered LUN: SCSIid $scsiId on $path"

    # SCSIid is all lvmohba needs. (The probe's <path> is for display: on a real host it reads
    # like "/dev/sde [sdc] [sdg] [sdi]", one entry per path.)
    $deviceConfig = @{ SCSIid = $scsiId }

    # SCSIid alone is also enough to probe the LUN itself: an <SR> in the answer means one is already
    # there, and SR.create would format it. Reattach that SR rather than destroying it.
    $probe = Invoke-XenSR -Ref "OpaqueRef:NULL" -XenAction Probe -XenHost $xenHost.opaque_ref `
        -DeviceConfig $deviceConfig -Type lvmohba -SmConfig @{} -PassThru
    $existing = @(([xml]$probe).SelectNodes('/SRlist/SR'))
    if ($existing.Count -gt 0) {
        throw "LUN $scsiId already holds SR $("$($existing[0].UUID)".Trim()); creating an SR here would " +
            "format it - reattach the existing SR instead of creating a new one"
    }

    $sr = New-XenSR -XenHost $xenHost -DeviceConfig $deviceConfig -PhysicalSize 0 `
        -NameLabel $SrName -NameDescription "HBA SR created by the SDK example" `
        -Type "lvmohba" -ContentType "user" -Shared $true -PassThru
    Write-Host "Created SR: $($sr.uuid) ($([math]::Floor([long]($sr.physical_size) / 1GB)) GiB)"
    # Tidy up: this example created the SR, so destroy it - a forgotten SR would stay on the LUN.
    # SR.destroy needs it detached from every host first.
    Get-XenPBD | Where-Object { $_.SR.opaque_ref -eq $sr.opaque_ref -and $_.currently_attached } |
        ForEach-Object { $_ | Invoke-XenPBD -XenAction Unplug }
    Remove-XenSR -Ref $sr.opaque_ref
    Write-Host "OK: create-hba-sr"
    $session | Disconnect-XenServer
}
```

<details><summary>Sample output</summary>

```text
Discovered LUN: SCSIid 360a980004265656d5f4a2d63764e5736 on /dev/sdb [sdc]
Created SR: 00000001-0000-0000-e20a-000000000000 (512 GiB)
OK: create-hba-sr
```

</details>

## xe CLI

Source: [`cli/storage/create-hba-sr.sh`](../../cli/storage/create-hba-sr.sh)

```bash
# Create an HBA SR.
#
# Connect a shared storage repository to a fibre-channel (HBA) LUN: discover the LUNs the host can see with a
# deliberately failing probe, then create the SR by SCSI ID. Creating the SR formats the LUN.
#
# Run it:
#   ./workflows.sh create-hba-sr https://xenserver root "$password"
#
# Optional key=value arguments (default):
#   sr_name (xe-example-hba)
#   scsi_id ("")

# No required parameter: discovery needs none. Probing with no SCSIid fails on purpose and lists every LUN
# the backend can see; the root element name and SR_BACKEND_FAILURE_<n> code both vary between XenServer
# versions, so parse by tag name wherever BlockDevice occurs. sr-create formats the chosen LUN -
# destructive.
create_hba_sr() {
    local sr_name h xml block scsi_id path sr
    sr_name=$(param sr_name "xe-example-hba")
    h=$(first_host)
    xml=$(probe_for_failure lvmohba host-uuid="$h")
    # sr-create formats the LUN: on shared FC storage name yours (scsi_id=); with none, the first is taken.
    local want rest
    want=$(param scsi_id "")
    rest=$xml
    while [[ $rest == *"<BlockDevice>"* ]]; do
        block=${rest#*<BlockDevice>}; rest=${block#*</BlockDevice>}; block="<BlockDevice>${block%%</BlockDevice>*}"
        scsi_id=$(xml_tag_text "$block" SCSIid)
        [ -z "$want" ] || [ "$scsi_id" = "$want" ] && break
        scsi_id=""
    done
    [ -n "$scsi_id" ] || { echo "no LUN with SCSIid $want is visible to this host" >&2; return 1; }
    path=$(xml_tag_text "$block" path)
    echo "Discovered LUN: SCSIid $scsi_id on $path"

    # SCSIid is all lvmohba needs. (The probe's <path> is for display: on a real host it reads
    # like "/dev/sde [sdc] [sdg] [sdi]", one entry per path.)
    #
    # SCSIid alone is also enough to probe the LUN itself: an <SR> in the answer means one is already
    # there, and sr-create would format it. Reattach that SR rather than destroying it.
    local existing_xml uuid
    existing_xml=$(xe sr-probe type=lvmohba device-config:SCSIid="$scsi_id")
    if uuid=$(xml_tag_text "$existing_xml" UUID); then
        echo "LUN $scsi_id already holds SR $uuid; creating an SR here would format it - reattach the" \
             "existing SR instead of creating a new one" >&2
        return 1
    fi

    sr=$(xe sr-create host-uuid="$h" type=lvmohba name-label="$sr_name" shared=true \
        device-config:SCSIid="$scsi_id")
    echo "Created HBA SR: $sr ($(( $(xe sr-param-get uuid=$sr param-name=physical-size) / 1024 / 1024 / 1024 )) GiB)"
    # Tidy up: this example created the SR, so destroy it - a forgotten SR would stay on the LUN.
    # SR.destroy needs it detached from every host first.
    for pbd in $(each_csv "$(xe pbd-list sr-uuid=$sr currently-attached=true --minimal)"); do
        xe pbd-unplug uuid=$pbd
    done
    xe sr-destroy uuid=$sr
    echo "OK: create-hba-sr"
}
```

<details><summary>Sample output</summary>

```text
Discovered LUN: SCSIid 360a980004265656d5f4a2d63764e5736 on /dev/sdb [sdc]
Created HBA SR: 00000001-0000-0000-7a0a-000000000000 (512 GiB)
OK: create-hba-sr
```

</details>
