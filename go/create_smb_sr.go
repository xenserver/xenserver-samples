package main

import (
	"fmt"

	"go/xenapi"
)

// createSmbSr - Create an SMB SR.
//
// Connect a shared storage repository to an SMB/CIFS file share, passing the server, share path and
// credentials (the password as a secret, never in plain text).
//
// Connect a shared SR to an SMB/CIFS file share. The password travels as a Secret, not plaintext
// device-config.
func createSmbSr(url, user, password, server, share, smbUsername, smbPassword, srName string) {
	const GiB = 1024 * 1024 * 1024
	session := connect(url, user, password)
	hosts, err := xenapi.Host.GetAll(session)
	check(err)
	host := hosts[0]

	secret, err := xenapi.Secret.Create(session, xenapi.SecretRecord{
		Value: smbPassword, OtherConfig: map[string]string{},
	})
	check(err)
	secretUUID, err := xenapi.Secret.GetUUID(session, secret)
	check(err)
	// server is the share as one UNC path, //server/share: the SMB driver has no separate serverpath.
	dc := map[string]string{
		"server": "//" + server + share, "username": smbUsername,
		"password_secret": secretUUID,
	}
	sr, err := xenapi.SR.Create(session, host, dc, 0, srName,
		"SMB SR created by the SDK example", "smb", "user", true, map[string]string{})
	check(err)
	size, _ := xenapi.SR.GetPhysicalSize(session, sr)
	uuid, _ := xenapi.SR.GetUUID(session, sr)
	fmt.Printf("Created SR: %s (%d GiB)\n", uuid, size/GiB)
	detachAndForgetSR(session, sr)
	check(xenapi.Secret.Destroy(session, secret))
	fmt.Println("OK: create-smb-sr")
	session.Logout()
}
