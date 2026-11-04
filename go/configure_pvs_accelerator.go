package main

import (
	"fmt"
	"sort"
	"strconv"

	"go/xenapi"
)

// configurePvsAccelerator - Configure PVS Accelerator.
//
// Build a PVS Accelerator site from nothing and take it down again: introduce the site and a PVS
// server, put a read cache on each host's local storage, accelerate a VM by proxying its first NIC,
// then forget the site — which cascades to everything hanging off it.
func configurePvsAccelerator(url, user, password, vmName string) {
	session := connect(url, user, password)
	defer session.Logout()

	// Check the VM first, before creating anything: it needs a NIC for the proxy to sit on. It need
	// not be running - a proxy on a halted VM just reports "stopped" until it starts.
	vm := vmByName(session, vmName)
	vifs, err := xenapi.VM.GetVIFs(session, vm)
	check(err)
	if len(vifs) == 0 {
		panic(fmt.Sprintf("%s has no network interface to accelerate", vmName))
	}
	// A proxy may only sit on the VM's LOWEST-numbered NIC, so sort by device rather than taking
	// VIFs[0] — the list comes back in creation order, which is the same thing only by luck.
	sort.Slice(vifs, func(i, j int) bool { return vifDevice(session, vifs[i]) < vifDevice(session, vifs[j]) })
	// ... and one that no site accelerates yet (a VIF takes one proxy: PVS_PROXY_ALREADY_PRESENT).
	proxies, err := xenapi.PVSProxy.GetAllRecords(session)
	check(err)
	for _, proxy := range proxies {
		if proxy.VIF == vifs[0] {
			siteName, _ := xenapi.PVSSite.GetNameLabel(session, proxy.Site)
			panic(fmt.Sprintf("%s is already accelerated by site '%s'", vmName, siteName))
		}
	}

	site, err := xenapi.PVSSite.Introduce(session, "sdk-example-pvs", "Created by the SDK examples", "")
	check(err)
	_, err = xenapi.PVSServer.Introduce(session, []string{"203.0.113.90"}, 6910, 6930, site)
	check(err)

	// The read cache must be on LOCAL storage. The point of the accelerator is to keep reads off the
	// network, so a cache on a shared SR would defeat it and the server rejects one.
	hosts, err := xenapi.Host.GetAll(session)
	check(err)
	for _, host := range hosts {
		local, ok := localSR(session, host)
		if !ok {
			continue
		}
		_, err = xenapi.PVSCacheStorage.Create(session, xenapi.PVSCacheStorageRecord{
			Host: host, SR: local, Site: site, Size: 10 * 1024 * 1024 * 1024,
		})
		check(err)
	}

	// A proxy may only sit on the VM's LOWEST-numbered NIC, hence sorting by device above rather than
	// taking VIFs[0] — the list comes back in creation order, which is the same thing only by luck.
	proxy, err := xenapi.PVSProxy.Create(session, site, vifs[0])
	check(err)

	record, err := xenapi.PVSSite.GetRecord(session, site)
	check(err)
	fmt.Printf("Site '%s' with %d cache(s) and %d server(s)\n",
		record.NameLabel, len(record.CacheStorage), len(record.Servers))
	// "caching" means it is actually accelerating. A site with no cache storage reports "initialised",
	// and a proxy on a VM whose NIC is unplugged reports "stopped".
	status, err := xenapi.PVSProxy.GetStatus(session, proxy)
	check(err)
	vmLabel, _ := xenapi.VM.GetNameLabel(session, vm)
	fmt.Printf("  %s: %s\n", vmLabel, status)

	// Forgetting the site only cascades its cache storage - a running proxy or a server it still
	// has makes forget refuse with PVS_SITE_CONTAINS_RUNNING_PROXIES/_SERVERS, so tear those down
	// ourselves first, in the same order every real PVS teardown uses. (Cache storage doesn't need
	// a separate call - forget cascades it correctly.)
	check(xenapi.PVSProxy.Destroy(session, proxy))
	servers, err := xenapi.PVSSite.GetServers(session, site)
	check(err)
	for _, server := range servers {
		check(xenapi.PVSServer.Forget(session, server))
	}
	check(xenapi.PVSSite.Forget(session, site))
	fmt.Println("OK: configure-pvs-accelerator")
}

// localSR returns the host's own non-ISO storage, found through its PBDs.
func localSR(session *xenapi.Session, host xenapi.HostRef) (xenapi.SRRef, bool) {
	pbds, err := xenapi.Host.GetPBDs(session, host)
	check(err)
	for _, pbd := range pbds {
		ref, err := xenapi.PBD.GetSR(session, pbd)
		check(err)
		sr, err := xenapi.SR.GetRecord(session, ref)
		check(err)
		if !sr.Shared && sr.ContentType != "iso" && sr.Type != "udev" {
			return ref, true
		}
	}
	return "", false
}

func vifDevice(session *xenapi.Session, vif xenapi.VIFRef) int {
	device, err := xenapi.VIF.GetDevice(session, vif)
	check(err)
	n, _ := strconv.Atoi(device)
	return n
}
