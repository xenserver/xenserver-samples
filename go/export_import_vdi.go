package main

import (
	"bytes"
	"crypto/rand"
	"crypto/sha256"
	"fmt"
	"io"
	"net/http"
	"time"

	"go/xenapi"
)

// exportImportVdi - Copy a disk's contents.
//
// Upload data into a virtual disk, download the disk's raw contents and copy them into a second disk,
// then check that the copy matches. Disk contents travel as HTTP transfers alongside the API.
//
// A disk's contents are not XenAPI calls: GET /export_raw_vdi reads them and PUT /import_raw_vdi
// writes them, both alongside the API with the session id in the query string. format=raw is every
// byte of the disk, so a raw export is as large as the disk's virtual size (format=vhd sends only the
// allocated blocks). Name a task in task_id to learn how the transfer ended: an HTTP 200 only means
// the server accepted the request.
//
// Run it:
//
//	exportImportVdi("https://xenserver", "root", password, "Shared NFS")
func exportImportVdi(url, user, password, srName string) {
	session := connect(url, user, password)
	defer session.Logout()
	// The Go binding keeps its own session id private, so log in once more for the HTTP transfers.
	sid := rawLogin(url, user, password)
	defer rawRPC(url, "session.logout", sid)
	sr := srByName(session, srName, false)
	const size = 8 * 1024 * 1024

	newDisk := func(name string) xenapi.VDIRef {
		vdi, err := xenapi.VDI.Create(session, xenapi.VDIRecord{
			NameLabel:   name,
			SR:          sr,
			VirtualSize: size,
			Type:        xenapi.VdiTypeUser,
			OtherConfig: map[string]string{},
		})
		check(err)
		return vdi
	}

	// One raw transfer of a disk's contents, waiting for its task to finish.
	transfer := func(method, path string, vdi xenapi.VDIRef, data []byte) []byte {
		task, err := xenapi.Task.Create(session, "sdk-example-"+path, "")
		check(err)
		defer xenapi.Task.Destroy(session, task)
		var body io.Reader
		if data != nil {
			body = bytes.NewReader(data)
		}
		request, err := http.NewRequest(method,
			fmt.Sprintf("%s/%s?session_id=%s&task_id=%s&vdi=%s&format=raw", url, path, sid, task, vdi), body)
		check(err)
		response, err := insecureClient().Do(request)
		check(err)
		received, err := io.ReadAll(response.Body)
		response.Body.Close()
		check(err)

		for {
			status, err := xenapi.Task.GetStatus(session, task)
			check(err)
			if status != xenapi.TaskStatusTypePending {
				break
			}
			time.Sleep(500 * time.Millisecond)
		}
		if status, _ := xenapi.Task.GetStatus(session, task); status != xenapi.TaskStatusTypeSuccess {
			errInfo, _ := xenapi.Task.GetErrorInfo(session, task)
			panic(fmt.Sprintf("%s failed: %v", path, errInfo))
		}
		return received
	}

	original := newDisk("sdk-example-raw-source")
	copied := newDisk("sdk-example-raw-copy")
	defer func() {
		check(xenapi.VDI.Destroy(session, original))
		check(xenapi.VDI.Destroy(session, copied))
	}()

	data := make([]byte, size)
	_, err := rand.Read(data)
	check(err)
	transfer(http.MethodPut, "import_raw_vdi", original, data)
	name, _ := xenapi.VDI.GetNameLabel(session, original)
	fmt.Printf("Uploaded %d MiB into %s\n", size/(1024*1024), name)

	exported := transfer(http.MethodGet, "export_raw_vdi", original, nil)
	fmt.Printf("Downloaded %d MiB of raw contents\n", len(exported)/(1024*1024))

	transfer(http.MethodPut, "import_raw_vdi", copied, exported)
	name, _ = xenapi.VDI.GetNameLabel(session, copied)
	fmt.Printf("Copied them into %s\n", name)

	same := sha256.Sum256(transfer(http.MethodGet, "export_raw_vdi", copied, nil)) == sha256.Sum256(data)
	if !same {
		fmt.Println("The copy DIFFERS FROM the original")
		panic("the copied disk does not match the data uploaded")
	}
	fmt.Println("The copy matches the original")
	fmt.Println("OK: export-import-vdi")
}
