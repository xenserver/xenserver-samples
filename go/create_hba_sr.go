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
// Connect a shared SR to a fibre-channel (HBA) LUN, discovering it first: probing with no SCSIid
// fails on purpose and lists every LUN the backend can see. The failure's XML root element name
// and error code both vary between XenServer versions, so parse by tag name BlockDevice wherever
// it occurs.
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
