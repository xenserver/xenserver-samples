package main

import (
	"fmt"

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

	// SCSIid is all lvmohba needs - it is what XenCenter's New SR wizard sends. (The probe's <path> is
	// for display: on a real host it reads like "/dev/sde [sdc] [sdg] [sdi]", one entry per path.)
	dc := map[string]string{"SCSIid": device["SCSIid"]}
	sr, err := xenapi.SR.Create(session, host, dc, 0, srName,
		"HBA SR created by the SDK example", "lvmohba", "user", true, map[string]string{})
	check(err)
	size, _ := xenapi.SR.GetPhysicalSize(session, sr)
	uuid, _ := xenapi.SR.GetUUID(session, sr)
	fmt.Printf("Created SR: %s (%d GiB)\n", uuid, size/GiB)
	detachAndForgetSR(session, sr)
	fmt.Println("OK: create-hba-sr")
	session.Logout()
}
