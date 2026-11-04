package main

import (
	"fmt"

	"go/xenapi"
)

// createNfsSR - Create an NFS SR.
//
// Create a shared NFS storage repository on an NFS export (nfs_server, nfs_path), then detach and
// forget it.
//
// Run it:
//
//	createNfsSR("https://xenserver", "root", password, "192.0.2.10", "/export/sdk", "sdk-example-nfs")
func createNfsSR(url, user, password, nfsServer, nfsPath, srName string) {
	session := connect(url, user, password)
	hosts, err := xenapi.Host.GetAllRecords(session)
	check(err)
	var hostRef xenapi.HostRef
	for ref := range hosts {
		hostRef = ref
		break
	}

	deviceConfig := map[string]string{
		"server":     nfsServer,
		"serverpath": nfsPath,
		"nfsversion": "3",
	}
	srRef, err := xenapi.SR.Create(session, hostRef, deviceConfig, 0,
		srName, "NFS SR created by the SDK example",
		"nfs", "user", true, map[string]string{})
	check(err)
	uuid, _ := xenapi.SR.GetUUID(session, srRef)
	fmt.Printf("Created SR: %s\n", uuid)

	detachAndForgetSR(session, srRef)
	fmt.Println("OK: create-nfs-sr")
	session.Logout()
}
