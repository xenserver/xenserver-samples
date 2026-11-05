package main

import (
	"fmt"

	"go/xenapi"
)

// configureClustering - Configure clustering.
//
// Enable the clustering layer that shared block storage needs for thin provisioning, then watch
// quorum as a host leaves the cluster and rejoins it.
func configureClustering(url, user, password string) {
	session := connect(url, user, password)

	// Clustering is what shared block storage needs before GFS2 thin provisioning. Run it over a network
	// every host is on - the management network - since corosync is latency-sensitive and a cluster that
	// loses quorum takes its GFS2 storage offline with it.
	pifs, err := xenapi.PIF.GetAllRecords(session)
	check(err)
	var network xenapi.NetworkRef
	for _, p := range pifs {
		if p.Management {
			network = p.Network
			break
		}
	}
	was := map[xenapi.PIFRef]bool{}
	for ref, p := range pifs {
		if p.Network == network {
			was[ref] = p.DisallowUnplug
		}
	}

	existing, err := xenapi.Cluster.GetAll(session)
	check(err)
	var cluster xenapi.ClusterRef
	if len(existing) > 0 {
		cluster = existing[0]
	} else {
		// Corosync must not lose its network, so each host's PIF on it has to refuse unplugging first:
		// Cluster.PoolCreate fails PIF_ALLOWS_UNPLUG otherwise. was remembers the settings to restore.
		for ref := range was {
			check(xenapi.PIF.SetDisallowUnplug(session, ref, true))
		}
		// token_timeout is in seconds (the API's default is 20.0, coefficient 1.0): XS9 refuses 20000 as
		// "too large" - it is not milliseconds.
		cluster, err = xenapi.Cluster.PoolCreate(session, network, "corosync", 20.0, 1.0)
		check(err)
	}

	stack, _ := xenapi.Cluster.GetClusterStack(session, cluster)
	quorate, _ := xenapi.Cluster.GetIsQuorate(session, cluster)
	live, _ := xenapi.Cluster.GetLiveHosts(session, cluster)
	quorum, _ := xenapi.Cluster.GetQuorum(session, cluster)
	fmt.Printf("Stack:      %s\n", stack)
	fmt.Printf("Quorate:    %t (%d/%d needed)\n", quorate, live, quorum)

	// Taking a host out is what a management-interface change does; it can cost quorum.
	members, err := xenapi.ClusterHost.GetAll(session)
	check(err)
	check(xenapi.ClusterHost.Disable(session, members[0]))
	quorate, _ = xenapi.Cluster.GetIsQuorate(session, cluster)
	fmt.Printf("One member out, quorate: %t\n", quorate)

	check(xenapi.ClusterHost.Enable(session, members[0]))
	check(xenapi.Cluster.PoolResync(session, cluster))
	quorate, _ = xenapi.Cluster.GetIsQuorate(session, cluster)
	fmt.Printf("Resynced,   quorate: %t\n", quorate)

	// Tidy up a cluster this example created (one that was already there stays), and the PIF settings.
	if len(existing) == 0 {
		check(xenapi.Cluster.PoolDestroy(session, cluster))
		for ref, v := range was {
			check(xenapi.PIF.SetDisallowUnplug(session, ref, v))
		}
		fmt.Println("Cluster removed again.")
	}

	fmt.Println("OK: configure-clustering")
	session.Logout()
}
