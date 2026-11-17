package main

import (
	"fmt"

	"go/xenapi"
)

// createIsoSr - Create an ISO library SR.
//
// Connect an ISO-library storage repository to a file share of ISO images (here an NFS export), so
// the images are available as installation media.
//
// Connect an ISO-library SR to a file share of ISO images (here an NFS export, location
// "server:/path").
func createIsoSR(url, user, password, location string) {
	session := connect(url, user, password)
	defer session.Logout()
	hosts, err := xenapi.Host.GetAll(session)
	check(err)
	dc := map[string]string{"location": location, "type": "nfs_iso"}
	sr, err := xenapi.SR.Create(session, hosts[0], dc, 0, "sdk-example-iso",
		"ISO library created by the SDK example", "iso", "iso", true, map[string]string{})
	check(err)
	uuid, _ := xenapi.SR.GetUUID(session, sr)
	fmt.Printf("Created ISO SR: %s\n", uuid)

	// A scan picks up the ISOs on the share as VDIs, which is what makes them selectable as
	// installation media.
	check(xenapi.SR.Scan(session, sr))
	vdis, err := xenapi.SR.GetVDIs(session, sr)
	check(err)
	fmt.Printf("ISO images: %d\n", len(vdis))

	detachAndForgetSR(session, sr)
	fmt.Println("Detached and forgot the SR.")
	fmt.Println("OK: create-iso-sr")
}
