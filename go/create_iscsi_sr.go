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
// the LUNs behind one. Creating the SR formats the LUN, and a shared array offers many targets, so
// name yours with target_iqn; if the target behind it offers more than one LUN, name yours with
// scsi_id too.
//
// Connect an SR to a LUN on the iSCSI target, discovering the IQN and the LUN first: a device-config that's
// missing a piece makes the backend fail on purpose, and the failure carries an XML fragment listing what it
// needs next.
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
// offer), else the one LUN, if that target offers only one. Choose a LUN automatically only when
// exactly one is on offer, and otherwise make the caller choose - picking blindly on a shared
// target risks formatting someone else's disk.
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
