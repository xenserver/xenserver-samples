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

// configureOfflineUpdates - Configure updates for an air-gapped pool.
//
// Switch a pool with no internet access to offline updates: make an update bundle repository the
// pool's only repository, upload an update bundle (.xsbundle) to it if you have one, list the updates
// it makes available, then tidy up.
//
// A pool that cannot reach the CDN takes its updates from a bundle you download elsewhere. The pool
// needs a repository of the bundle kind (it can have only one: Repository.introduce_bundle refuses a
// second with BUNDLE_REPOSITORY_ALREADY_EXISTS, so use the existing one), and it must be the pool's only
// enabled repository. Uploading is an HTTP PUT to /bundle alongside the API, with the session id and a
// task in the query string: the pool unpacks and checks the bundle, and the task says how that went.
// GET /updates then lists what the bundle offers each host, and host.apply_updates applies it with the
// hash in that list (see applyUpdate). With an empty bundlePath this only switches the channel and back.
//
// Run it:
//
//	configureOfflineUpdates("https://xenserver", "root", password, "XS9-update.xsbundle")
func configureOfflineUpdates(url, user, password, bundlePath string) {
	session := connect(url, user, password)
	defer session.Logout()
	pools, err := xenapi.Pool.GetAll(session)
	check(err)
	pool := pools[0]

	// Remember the pool's own repositories, to put them back afterwards.
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

	if bundlePath == "" {
		fmt.Println("No bundle given: pass bundle_path to upload one")
		fmt.Println("OK: configure-offline-updates")
		return
	}

	// The Go binding keeps its own session id private, so log in once more for the HTTP transfers.
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
		Hash    string            `json:"hash"`
		Updates []json.RawMessage `json:"updates"`
	}
	check(json.NewDecoder(response.Body).Decode(&available))
	fmt.Printf("Updates in the bundle: %d (apply them with hash %s)\n", len(available.Updates), available.Hash)
	fmt.Println("OK: configure-offline-updates")
}
