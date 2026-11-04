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
// array offers many targets, so name yours with target_iqn.
//
// Connect an SR to a LUN on the iSCSI target, discovering the IQN and the LUN the way the New SR
// wizard does: a device-config that's missing a piece makes the backend fail on purpose, and the
// failure carries an XML fragment listing what it needs next.
//
// SR.create formats the chosen LUN - this is destructive, so pick carefully on a real target: pass
// targetIQN to name yours (see chooseTargetIQN).
func createIscsiSr(url, user, password, target, port, chapUser, chapPassword, targetIQN, srName string) {
	const GiB = 1024 * 1024 * 1024
	session := connect(url, user, password)
	hosts, err := xenapi.Host.GetAll(session)
	check(err)
	host := hosts[0]
	dc := map[string]string{"target": target}
	if port != "" {
		dc["port"] = port
	}
	if chapUser != "" {
		dc["chapuser"] = chapUser
		dc["chappassword"] = chapPassword
	}

	// First failing probe: target only -> the backend lists the IQNs it offers.
	dc["targetIQN"] = chooseTargetIQN(probeForFailure(session, host, dc, "lvmoiscsi"), target, targetIQN)
	fmt.Printf("Discovered IQN: %s\n", dc["targetIQN"])

	// Second failing probe: +targetIQN -> the backend lists the LUNs behind it. Real create also
	// carries LUNid whenever it is known; fall back to the first LUN's list index (0) if the
	// backend doesn't report one.
	lun := firstXMLElement(probeForFailure(session, host, dc, "lvmoiscsi"), "LUN")
	dc["SCSIid"] = lun["SCSIid"]
	if id := lun["LUNid"]; id != "" {
		dc["LUNid"] = id
	} else {
		dc["LUNid"] = "0"
	}
	fmt.Printf("Discovered LUN %s (SCSIid %s)\n", dc["LUNid"], dc["SCSIid"])

	sr, err := xenapi.SR.Create(session, host, dc, 0, srName,
		"iSCSI SR created by the SDK example", "lvmoiscsi", "user", true, map[string]string{})
	check(err)
	size, _ := xenapi.SR.GetPhysicalSize(session, sr)
	uuid, _ := xenapi.SR.GetUUID(session, sr)
	fmt.Printf("Created SR: %s (%d GiB)\n", uuid, size/GiB)
	detachAndForgetSR(session, sr)
	fmt.Println("OK: create-iscsi-sr")
	session.Logout()
}

// firstXMLElement scans an XML document for the first element named tag, at any depth (the root
// element name and nesting both vary by host/backend - the probe helpers below must not assume
// either), and returns a map of its immediate child elements' tag name to text content.
func firstXMLElement(xmlText, tag string) map[string]string {
	return findXMLElement(xmlText, tag, "", "")
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
