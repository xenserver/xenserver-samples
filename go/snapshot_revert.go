package main

import (
	"fmt"
	"io"
	"net/http"
	"time"

	"go/xenapi"
)

// snapshotRevert - Snapshot & revert.
//
// Take a snapshot of a VM and then revert the VM back to that point-in-time, as you would before a
// risky change.
//
// Run it:
//
//	snapshotRevert("https://xenserver", "root", password, "web-01", "sdk-example-snapshot")
func snapshotRevert(url, user, password, vmName, snapshotName string) {
	session := connect(url, user, password)
	defer session.Logout()
	vmRef := vmByName(session, vmName)
	name, _ := xenapi.VM.GetNameLabel(session, vmRef)
	fmt.Printf("Snapshotting VM: %s\n", name)
	wasRunning := false
	if state, _ := xenapi.VM.GetPowerState(session, vmRef); state == xenapi.VMPowerStateRunning {
		wasRunning = true
	}

	snapRef, err := xenapi.VM.Snapshot(session, vmRef, snapshotName, nil)
	check(err)
	uuid, _ := xenapi.VM.GetUUID(session, snapRef)
	fmt.Printf("Created snapshot: %s\n", uuid)

	// A client shows a thumbnail of what was on screen when the snapshot was taken, captured from the VM's
	// console at that moment. It is an HTTP transfer alongside the API, not an API call, so the session id
	// travels in the query string. ref names the VM's VNC (rfb) console (the VM itself works too). Only a
	// running VM has a console to capture, and a host that can't reach it answers 404 or 500 instead of an
	// image: the picture is incidental, so carry on. The Go binding keeps its own session private, so
	// obtain one of our own the same way the RRD/export examples do.
	if state, _ := xenapi.VM.GetPowerState(session, vmRef); state == xenapi.VMPowerStateRunning {
		consoles, err := xenapi.VM.GetConsoles(session, vmRef)
		check(err)
		var console xenapi.ConsoleRef
		for _, c := range consoles {
			if p, err := xenapi.Console.GetProtocol(session, c); err == nil && p == xenapi.ConsoleProtocolRfb {
				console = c
				break
			}
		}
		sid := rawLogin(url, user, password)
		// A host's 404 here can leave the connection open with no end to its body, so read the body only for
		// a picture, and bound the whole request.
		client := insecureClient()
		client.Timeout = 30 * time.Second
		resp, err := client.Get(fmt.Sprintf("%s/vncsnapshot?session_id=%s&ref=%s", url, sid, console))
		if err != nil {
			fmt.Printf("Thumbnail:      none (no answer: %v)\n", err)
		} else if resp.StatusCode != http.StatusOK {
			resp.Body.Close()
			fmt.Printf("Thumbnail:      none (the host answered HTTP %d)\n", resp.StatusCode)
		} else {
			thumb, err := io.ReadAll(resp.Body)
			resp.Body.Close()
			if err != nil {
				fmt.Printf("Thumbnail:      none (no answer: %v)\n", err)
			} else {
				fmt.Printf("Thumbnail:      %d bytes of PNG\n", len(thumb))
			}
		}
	} else {
		fmt.Println("Thumbnail:      none (the VM is not running, so it has no console)")
	}

	check(xenapi.VM.Revert(session, snapRef))
	fmt.Println("Reverted VM to the snapshot.")

	// Reverting to a plain snapshot always leaves the VM Halted (xapi hard-shuts-down a running VM
	// before reverting it), even if it was Running a moment ago - restart it if that is how we
	// found it, so the workflow actually restores what it changed.
	if wasRunning {
		check(xenapi.VM.Start(session, vmRef, false, true))
		fmt.Println("Restarted the VM (it was running before the revert).")
	}

	// A snapshot is itself a (special) VM record, with its own snapshot disks; destroy both to clean up
	// (the source VM's disks are untouched - they are not the snapshot's).
	destroyVMAndDisks(session, snapRef)
	fmt.Println("OK: snapshot-revert")
}
