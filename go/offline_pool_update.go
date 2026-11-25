package main

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"time"

	"go/xenapi"
)

// offlinePoolUpdate - Update an air-gapped pool from a bundle.
//
// Update a pool with no internet access from an update bundle (.xsbundle) downloaded elsewhere: make
// a bundle repository the pool's update repository, upload the bundle, list the updates it offers,
// then apply them host by host - coordinator first, moving each host's VMs to the rest of the pool -
// so the VMs keep running throughout.
//
// Check first, before changing anything, that the update can go through: HA and Workload Balancing
// off, no host or VM with mandatory guidance still pending from an earlier update, and every host
// able to empty. Then make a repository of the bundle kind the pool's only enabled repository - a
// pool can have only one (Repository.IntroduceBundle refuses a second with
// BUNDLE_REPOSITORY_ALREADY_EXISTS), so use the existing one if there is one. uploadBundle uploads
// the bundle and lists what it offers, and updateHosts applies it to each host in turn as
// rolling-pool-update does. Finally report the guidance left for VMs, such as restarting one to pick
// the update up - that is the VM owner's call.
//
// A pool that stays air-gapped keeps its bundle repository for the next bundle; this example puts the
// pool's previous repositories back afterwards so that it can run again on a test pool.
func offlinePoolUpdate(url, user, password, bundlePath string) {
	session := connect(url, user, password)
	// Deferred first, so it runs LAST: after the deferred repository restore below, which needs
	// the session. A closure, so it logs out whichever session is current by then.
	defer func() { session.Logout() }()
	pools, err := xenapi.Pool.GetAll(session)
	check(err)
	pool := pools[0]
	hosts := hostsCoordinatorFirst(session)
	checkHaAndWlbOff(session, pool)
	checkNoPendingGuidance(session)
	checkHostsCanBeEvacuated(session, hosts)

	previous, err := xenapi.Pool.GetRepositories(session, pool)
	check(err)
	repos, err := xenapi.Repository.GetAllRecords(session)
	check(err)
	var repo xenapi.RepositoryRef
	for ref, record := range repos {
		if record.Origin == xenapi.OriginBundle {
			repo = ref
		}
	}
	introduced := repo == ""
	if introduced {
		repo, err = xenapi.Repository.IntroduceBundle(session, "sdk-example-offline", "Updates from uploaded bundles")
		check(err)
	}
	defer func() {
		// Forgetting a repository the pool still has enabled fails (REPOSITORY_IS_IN_USE): restore first.
		check(xenapi.Pool.SetRepositories(session, pool, previous))
		if introduced {
			check(xenapi.Repository.Forget(session, repo))
		}
	}()

	check(xenapi.Pool.SetRepositories(session, pool, []xenapi.RepositoryRef{repo}))
	enabled, err := xenapi.Pool.GetRepositories(session, pool)
	check(err)
	for _, r := range enabled {
		name, _ := xenapi.Repository.GetNameLabel(session, r)
		fmt.Printf("Pool repositories: %s\n", name)
	}

	hash, count := uploadBundle(session, url, user, password, bundlePath)
	if count > 0 {
		session = updateHosts(session, url, user, password, hosts, hash)
	}
	reportVMGuidance(session)
	fmt.Println("OK: offline-pool-update")
}

// uploadBundle uploads the bundle at bundlePath to the pool's bundle repository, prints the updates it
// offers, and returns the hash to apply them with and how many there are.
//
// Uploading is an HTTP PUT to /bundle alongside the API, with the session id and a task in the query
// string. The server answers 200 before it has read the bundle, so the task says how it went: the
// pool unpacks the bundle, checks its signature and syncs its updates before the task completes. GET
// /updates then lists what the bundle offers and the hash to apply it with.
func uploadBundle(session *xenapi.Session, url, user, password, bundlePath string) (string, int) {
	// The Go binding keeps its own session id private, so log in once more for the HTTP transfers -
	// and out again here, before any host restarts.
	sid := rawLogin(url, user, password)
	defer rawRPC(url, "session.logout", sid)
	task, err := xenapi.Task.Create(session, "sdk-example-bundle-upload", "")
	check(err)
	defer xenapi.Task.Destroy(session, task)
	bundle, err := os.Open(bundlePath)
	check(err)
	defer bundle.Close()
	info, err := bundle.Stat()
	check(err)
	request, err := http.NewRequest(http.MethodPut,
		fmt.Sprintf("%s/bundle?session_id=%s&task_id=%s", url, sid, task), bundle)
	check(err)
	request.ContentLength = info.Size()
	response, err := insecureClient().Do(request)
	check(err)
	io.Copy(io.Discard, response.Body)
	response.Body.Close()
	for {
		status, err := xenapi.Task.GetStatus(session, task)
		check(err)
		if status != xenapi.TaskStatusTypePending {
			break
		}
		time.Sleep(time.Second)
	}
	if status, _ := xenapi.Task.GetStatus(session, task); status != xenapi.TaskStatusTypeSuccess {
		errInfo, _ := xenapi.Task.GetErrorInfo(session, task)
		panic(fmt.Sprintf("bundle upload failed: %v", errInfo))
	}
	fmt.Printf("Uploaded %s\n", filepath.Base(bundlePath))

	response, err = insecureClient().Get(fmt.Sprintf("%s/updates?session_id=%s", url, sid))
	check(err)
	defer response.Body.Close()
	var available struct {
		Hash    string `json:"hash"`
		Updates []struct {
			ID      string `json:"id"`
			Summary string `json:"summary"`
		} `json:"updates"`
	}
	check(json.NewDecoder(response.Body).Decode(&available))
	fmt.Printf("Updates in the bundle: %d\n", len(available.Updates))
	for _, update := range available.Updates {
		fmt.Printf("  %s: %s\n", update.ID, update.Summary)
	}
	return available.Hash, len(available.Updates)
}
