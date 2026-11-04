package main

import (
	"fmt"
	"strings"

	"go/xenapi"
)

// configureUpdates - Configure updates (CDN).
//
// Point the pool at a CDN update repository and turn on automatic update sync: register a
// repository, set it as the pool's repository, enable update sync, read it back, then tidy up.
//
// Run it:
//
//	configureUpdates("https://xenserver", "root", password, "https://repo.ops.xenserver.com/xs9",
//	"https://repo-src.ops.xenserver.com/xs9")
func configureUpdates(url, user, password, repoURL, sourceURL string) {
	session := connect(url, user, password)
	repos := introduceUpdateRepositories(session, repoURL, sourceURL)
	var names []string
	for _, repo := range repos {
		name, _ := xenapi.Repository.GetNameLabel(session, repo)
		names = append(names, name)
	}
	fmt.Printf("Introduced repositories: %s\n", strings.Join(names, ", "))

	pools, err := xenapi.Pool.GetAll(session)
	check(err)
	pool := pools[0]
	// Remember the pool's own repositories, to put them back afterwards.
	previous, perr := xenapi.Pool.GetRepositories(session, pool)
	check(perr)
	check(xenapi.Pool.SetRepositories(session, pool, repos))
	check(xenapi.Pool.SetUpdateSyncEnabled(session, pool, true))
	nowRepos, _ := xenapi.Pool.GetRepositories(session, pool)
	enabled, _ := xenapi.Pool.GetUpdateSyncEnabled(session, pool)
	fmt.Printf("Pool repositories: %d; auto-sync enabled: %v\n", len(nowRepos), enabled)

	// Tidy up so the example is repeatable.
	check(xenapi.Pool.SetUpdateSyncEnabled(session, pool, false))
	check(xenapi.Pool.SetRepositories(session, pool, previous))
	for _, repo := range repos {
		check(xenapi.Repository.Forget(session, repo))
	}
	fmt.Println("OK: configure-updates")
	session.Logout()
}
