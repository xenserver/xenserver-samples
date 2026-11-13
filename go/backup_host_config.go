package main

import (
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"time"

	"go/xenapi"
)

// backupHostConfig - Back up a host's configuration.
//
// Download a host's configuration backup and verify it downloaded; optionally stage it back onto that
// same host's backup partition, ready for a restore done from the installer.
//
// Both /host_backup and /host_restore are served only by whichever host physically accepted the
// HTTP connection - the handler ignores any ref= in the query string entirely, there is no
// forwarding to another pool member. So backing up/restoring a host means opening the connection
// to THAT host's own address, not to the pool's (coordinator) url. ref= is kept in the query string
// purely for log-readability (a real host ignores it).
//
// Both halves are hundreds of MB on a real host, so they stream to/from a temp file rather than
// holding the backup in memory. A transfer takes long enough on a slow link for the network to drop
// an API connection left idle meanwhile, and the next call would then hang on it until the socket
// timed out - so this session sends "Connection: close", giving every API call its own connection.
//
// restore stages the backup onto the SAME host's backup partition. host-restore does not restore the
// host there and then: it only writes the archive over that host's currently inactive backup
// partition, ready for the next boot. It takes effect only once that host is booted from the
// installer and Restore is chosen there.
func backupHostConfig(url, user, password string, restore bool) {
	session := xenapi.NewSession(&xenapi.ClientOpts{URL: url, Headers: map[string]string{"Connection": "close"}})
	_, err := session.LoginWithPassword(user, password, "1.0", "sdk-examples")
	check(err)
	defer session.Logout()

	// The coordinator: always reachable at the pool's address. (Back up every host, in practice.)
	pools, err := xenapi.Pool.GetAll(session)
	check(err)
	host, err := xenapi.Pool.GetMaster(session, pools[0])
	check(err)
	name, err := xenapi.Host.GetNameLabel(session, host)
	check(err)
	address, err := xenapi.Host.GetAddress(session, host)
	check(err)
	hostAddr := hostURL(url, address)
	fmt.Printf("Backing up %s\n", name)

	// Backup and restore are HTTP transfers alongside the API, not API calls, so the session id travels
	// in the query string. The Go binding keeps its own session private, so obtain one of our own.
	sid := rawLogin(url, user, password)
	temp, err := os.CreateTemp("", "sdk-example-host-*.backup")
	check(err)
	path := temp.Name()

	resp, err := insecureClient().Get(
		fmt.Sprintf("%s/host_backup?session_id=%s&ref=%s", hostAddr, sid, host))
	check(err)
	// Hundreds of MB on a real host: stream it to disk, don't hold it in memory.
	_, err = io.Copy(temp, resp.Body)
	check(err)
	resp.Body.Close()
	check(temp.Close())
	info, err := os.Stat(path)
	check(err)
	if info.Size() == 0 {
		panic(fmt.Sprintf("%s came back empty", path))
	}
	fmt.Printf("  wrote %d bytes to %s\n", info.Size(), filepath.Base(path))

	if restore {
		restoreHostConfig(session, hostAddr, sid, host, path)
		fmt.Printf("  staged it on %s's backup partition - it takes effect only after booting that host "+
			"from the installer and choosing Restore\n", name)
	} else {
		fmt.Printf("  not restoring it (pass restore=true to stage it on %s's backup partition)\n", name)
	}

	check(os.Remove(path))
	fmt.Println("OK: backup-host-config")
}

// hostURL rebuilds a URL for a different host's own address, keeping the original scheme and port
// (a host's management "address" field carries no port of its own). Needed anywhere a workflow
// does raw HTTP against a SPECIFIC host rather than the pool's connection URL.
func hostURL(rawURL, address string) string {
	u, err := url.Parse(rawURL)
	check(err)
	host := address
	if port := u.Port(); port != "" {
		host = address + ":" + port
	}
	return u.Scheme + "://" + host
}

// restoreHostConfig uploads a backup to a host - over a connection opened to THAT host's own
// address - and panics if the task reports it was refused.
//
// An upload answers 200 as soon as it has read the request headers, because the client waits for that
// before it starts sending the file. The outcome therefore cannot be in the status line: it arrives on a
// task you create first, name in the URL, and poll once the upload has finished.
func restoreHostConfig(session *xenapi.Session, url, sid string, host xenapi.HostRef, path string) {
	task, err := xenapi.Task.Create(session, "host_restore", "restoring a configuration backup")
	check(err)
	defer xenapi.Task.Destroy(session, task)

	file, err := os.Open(path)
	check(err)
	defer file.Close()
	info, err := os.Stat(path)
	check(err)

	// Stream the file as the request body rather than reading it into memory first: a real host's
	// backup is hundreds of MB. http.NewRequest can't infer the length of an arbitrary io.Reader, so
	// set ContentLength explicitly - without it Go would send chunked Transfer-Encoding, which isn't
	// what a real host's /host_restore handler expects.
	request, err := http.NewRequest(http.MethodPut,
		fmt.Sprintf("%s/host_restore?session_id=%s&ref=%s&task_id=%s", url, sid, host, task),
		file)
	check(err)
	request.ContentLength = info.Size()
	resp, err := insecureClient().Do(request)
	check(err)
	io.Copy(io.Discard, resp.Body)
	resp.Body.Close()

	for {
		status, err := xenapi.Task.GetStatus(session, task)
		check(err)
		if status != xenapi.TaskStatusTypePending {
			if status == xenapi.TaskStatusTypeSuccess {
				return
			}
			info, err := xenapi.Task.GetErrorInfo(session, task)
			check(err)
			panic(fmt.Sprintf("refused (%s)", info[len(info)-1]))
		}
		time.Sleep(500 * time.Millisecond)
	}
}
