package main

import (
	"archive/tar"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"time"

	"go/xenapi"
)

// exportImportVm - Export and import a VM.
//
// Export a VM to an XVA file and import it back as a new one. These are HTTP transfers alongside
// the API rather than API calls, so the session id travels in the query string.
//
// Run it:
//
//	exportImportVm("https://xenserver", "root", password, "db-01")
func exportImportVm(url, user, password, vmName string) {
	session := connect(url, user, password)
	defer session.Logout()

	// Name the VM: an export carries every block of its disks, so which VM matters (a large one takes a
	// long time, and fills the disk). Only a halted VM can be exported: its disks must not be changing
	// underneath the copy.
	vm := vmByName(session, vmName)
	powerState, err := xenapi.VM.GetPowerState(session, vm)
	check(err)
	if powerState != xenapi.VMPowerStateHalted {
		panic(fmt.Sprintf("%s must be halted to be exported", vmName))
	}
	fmt.Printf("Exporting %s\n", vmName)

	// Export and import are HTTP transfers alongside the API, not API calls, so the session id travels
	// in the query string. The Go binding keeps its own session private, so obtain one the same way the
	// RRD example does: a small JSON-RPC login of our own.
	sid := rawLogin(url, user, password)
	// A unique file, not a fixed name: an export is a real file on disk and two of them running at once
	// would otherwise fight over it.
	temp, err := os.CreateTemp("", "sdk-example-export-*.xva")
	check(err)
	path := temp.Name()
	temp.Close()
	// Always clean up the file, on failure too: a real export is gigabytes, not worth leaving behind.
	defer os.Remove(path)

	// Stream both directions: a real VM's export is gigabytes, too large to hold in memory.
	uuid, err := xenapi.VM.GetUUID(session, vm)
	check(err)
	resp, err := insecureClient().Get(fmt.Sprintf("%s/export?session_id=%s&uuid=%s", url, sid, uuid))
	check(err)
	out, err := os.Create(path)
	check(err)
	written, err := io.Copy(out, resp.Body)
	check(err)
	resp.Body.Close()
	out.Close()
	fmt.Printf("  wrote %.1f MiB to %s\n", float64(written)/(1024*1024), filepath.Base(path))

	// An XVA is a tar: ova.xml describes the VM, and the disk blocks follow in 1 MiB pieces, each with
	// its own checksum.
	names := tarNames(path)
	blocks := 0
	for _, n := range names {
		if !strings.HasSuffix(n, ".checksum") {
			blocks++
		}
	}
	fmt.Printf("  archive holds %s and %d disk block(s)\n", names[0], blocks-1)

	// The imported VM's ref is NOT in the /import response body on a real host - the only place it
	// appears is the task named in the task_id query parameter, so create one, pass it, and read
	// task.get_result() once the upload finishes (the same <value>...</value> string-strip
	// wait-for-task already uses).
	task, err := xenapi.Task.Create(session, "vm_import", "importing "+vmName+" back")
	check(err)
	defer xenapi.Task.Destroy(session, task)

	archive, err := os.Open(path)
	check(err)
	request, err := http.NewRequest(http.MethodPut,
		fmt.Sprintf("%s/import?session_id=%s&task_id=%s", url, sid, task), archive)
	check(err)
	info, err := archive.Stat()
	check(err)
	request.ContentLength = info.Size()
	putResp, err := insecureClient().Do(request)
	check(err)
	io.Copy(io.Discard, putResp.Body)
	putResp.Body.Close()
	archive.Close()

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
		panic(fmt.Sprintf("import failed: %v", errInfo))
	}
	result, err := xenapi.Task.GetResult(session, task)
	check(err)
	// The result lists the imported VMs (<value><array><data>OpaqueRef:...</data></array></value>
	// on a real host), so take the first reference in it.
	imported := xenapi.VMRef(regexp.MustCompile(`OpaqueRef:[^<]+`).FindString(result))
	name, err := xenapi.VM.GetNameLabel(session, imported)
	check(err)
	fmt.Printf("  imported as %s\n", name)

	// The import brought its own disks along; destroy those too, not just the VM record.
	destroyVMAndDisks(session, imported)
	fmt.Println("OK: export-import-vm")
}

// tarNames lists the entries of a tar archive.
func tarNames(path string) []string {
	file, err := os.Open(path)
	check(err)
	defer file.Close()
	var names []string
	reader := tar.NewReader(file)
	for {
		header, err := reader.Next()
		if err != nil {
			break
		}
		names = append(names, header.Name)
	}
	return names
}
