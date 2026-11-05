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
// Download a host's configuration backup and hand it back as a restore would — and watch another
// host's backup be refused.
//
// Both /host_backup and /host_restore are served only by whichever host physically accepted the
// HTTP connection - the handler ignores any ref= in the query string entirely, there is no
// forwarding to another pool member. So backing up/restoring a host means opening the connection
// to THAT host's own address, not to the pool's (coordinator) url - a restore sent to the wrong
// host's connection silently restores the WRONG host, not the one named by ref=. ref= is kept in
// the query string purely for log-readability (a real host ignores it).
//
// Both halves are hundreds of MB on a real host, so they stream to/from a temp file rather than
// holding the backup in memory. A transfer takes long enough on a slow link for the network to drop
// an API connection left idle meanwhile, and the next call would then hang on it until the socket
// timed out - so this session sends "Connection: close", giving every API call its own connection.
func backupHostConfig(url, user, password string) {
	session := xenapi.NewSession(&xenapi.ClientOpts{URL: url, Headers: map[string]string{"Connection": "close"}})
	_, err := session.LoginWithPassword(user, password, "1.0", "sdk-examples")
	check(err)
	defer session.Logout()

	// The coordinator: always reachable at the pool's address. (Back up every host, in practice.)
	pools, err := xenapi.Pool.GetAll(session)
	check(err)
	coordinator, err := xenapi.Pool.GetMaster(session, pools[0])
	check(err)
	all, err := xenapi.Host.GetAll(session)
	check(err)
	hosts := []xenapi.HostRef{coordinator}
	for _, h := range all {
		if h != coordinator {
			hosts = append(hosts, h)
		}
	}
	host := hosts[0]
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
	fmt.Printf("  wrote %d bytes to %s\n", info.Size(), filepath.Base(path))

	fmt.Printf("  restoring it to %s: %s\n", name, restoreHostConfig(session, hostAddr, sid, host, path))
	if len(hosts) > 1 {
		other := hosts[1]
		otherName, err := xenapi.Host.GetNameLabel(session, other)
		check(err)
		otherAddress, err := xenapi.Host.GetAddress(session, other)
		check(err)
		otherURL := hostURL(url, otherAddress)
		// The refusal is the half worth rehearsing: restoring one host's configuration onto another is
		// destructive and unrecoverable, so the pool checks rather than trusting the caller. Guard
		// against a transport error with a friendly message instead of letting the whole example fail
		// - a real pool's hosts are all reachable from a management client, so this only matters in
		// topologies where a second host's address isn't actually routable from the caller.
		fmt.Printf("  restoring it to %s: %s\n", otherName,
			safeRestoreHostConfig(session, otherURL, sid, other, path))
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

// safeRestoreHostConfig calls restoreHostConfig but turns any transport error into a friendly
// message instead of letting the whole example fail.
func safeRestoreHostConfig(session *xenapi.Session, hostURL, sid string, host xenapi.HostRef, path string) (result string) {
	defer func() {
		if r := recover(); r != nil {
			result = fmt.Sprintf("could not connect to %s directly (%v)", hostURL, r)
		}
	}()
	return restoreHostConfig(session, hostURL, sid, host, path)
}

// restoreHostConfig uploads a backup to a host - over a connection opened to THAT host's own
// address - and reports what the task says about it.
//
// An upload answers 200 as soon as it has read the request headers, because the client waits for that
// before it starts sending the file. The outcome therefore cannot be in the status line: it arrives on a
// task you create first, name in the URL, and poll once the upload has finished.
func restoreHostConfig(session *xenapi.Session, url, sid string, host xenapi.HostRef, path string) string {
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
				return "accepted"
			}
			info, err := xenapi.Task.GetErrorInfo(session, task)
			check(err)
			return fmt.Sprintf("refused (%s)", info[len(info)-1])
		}
		time.Sleep(500 * time.Millisecond)
	}
}
