package main

import (
	"fmt"

	"go/xenapi"
)

// reconnectSrStorage - Point an SR at moved storage.
//
// When the storage behind an SR moves to a new address, point the SR at it: a host's connection to an
// SR cannot be edited, so unplug each one, recreate it with the new settings and plug it back.
//
// Each host reaches an SR through a PBD, whose device_config (server, path, target, ...) says where
// the storage is. A PBD's device_config is fixed when it is created, so changing it means unplugging
// the PBD, destroying it, and creating and plugging a new one with the updated settings, host by host.
// The SR and its disks are untouched throughout. Every PBD has to be unplugged first, which needs every
// VM using the SR to be shut down. This example creates an NFS SR on nfsServer:nfsPath to work on, and
// forgets it again at the end; an empty newNfsServer reconnects the SR to the same storage.
//
// Run it:
//
//	reconnectSrStorage("https://xenserver", "root", password, "192.0.2.10", "/export/spare", "192.0.2.11")
func reconnectSrStorage(url, user, password, nfsServer, nfsPath, newNfsServer string) {
	session := connect(url, user, password)
	defer session.Logout()
	if newNfsServer == "" {
		newNfsServer = nfsServer
	}

	hosts, err := xenapi.Host.GetAll(session)
	check(err)
	sr, err := xenapi.SR.Create(session, hosts[0], map[string]string{
		"server":     nfsServer,
		"serverpath": nfsPath,
		"nfsversion": "3",
	}, 0, "sdk-example-moved-storage", "SR used by the SDK reconnect example",
		"nfs", "user", true, map[string]string{})
	check(err)
	// Tidy up: detach the SR from every host and forget it, leaving the storage itself untouched.
	defer detachAndForgetSR(session, sr)

	pbds, err := xenapi.SR.GetPBDs(session, sr)
	check(err)
	for _, pbd := range pbds {
		check(xenapi.PBD.Unplug(session, pbd))
	}

	for _, pbd := range pbds {
		record, err := xenapi.PBD.GetRecord(session, pbd)
		check(err)
		deviceConfig := map[string]string{}
		for k, v := range record.DeviceConfig {
			deviceConfig[k] = v
		}
		deviceConfig["server"] = newNfsServer
		check(xenapi.PBD.Destroy(session, pbd))
		replacement, err := xenapi.PBD.Create(session, xenapi.PBDRecord{
			Host:         record.Host,
			SR:           sr,
			DeviceConfig: deviceConfig,
			OtherConfig:  map[string]string{},
		})
		check(err)
		check(xenapi.PBD.Plug(session, replacement))
		name, _ := xenapi.Host.GetNameLabel(session, record.Host)
		fmt.Printf("%s: now reaches %s:%s\n", name, deviceConfig["server"], deviceConfig["serverpath"])
	}
	fmt.Println("OK: reconnect-sr-storage")
}
