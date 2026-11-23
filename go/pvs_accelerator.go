package main

import (
	"fmt"
	"strings"

	"go/xenapi"
)

// pvsAccelerator - PVS Accelerator inventory.
//
// Document a pool's Citrix Provisioning (PVS) Accelerator setup: each site's read cache (host,
// size, storage), its PVS servers (addresses and streaming port range), and which VMs are
// accelerated versus the whole pool.
//
// Run it:
//
//	pvsAccelerator("https://xenserver", "root", password)
func pvsAccelerator(url, user, password string) {
	session := connect(url, user, password)
	defer session.Logout()

	sites, err := xenapi.PVSSite.GetAllRecords(session)
	check(err)
	if len(sites) == 0 {
		fmt.Println("No PVS Accelerator sites are configured.")
	}
	for _, site := range sites {
		fmt.Printf("Site: %s\n", site.NameLabel)
		for _, csRef := range site.CacheStorage {
			cs, err := xenapi.PVSCacheStorage.GetRecord(session, csRef)
			check(err)
			host, _ := xenapi.Host.GetRecord(session, cs.Host)
			sr, _ := xenapi.SR.GetRecord(session, cs.SR)
			fmt.Printf("  cache:  %s  %d GiB on %s\n", host.NameLabel, cs.Size/(1024*1024*1024), sr.NameLabel)
		}
		for _, serverRef := range site.Servers {
			server, err := xenapi.PVSServer.GetRecord(session, serverRef)
			check(err)
			fmt.Printf("  server: %s  ports %d-%d\n", strings.Join(server.Addresses, ", "), server.FirstPort, server.LastPort)
		}
		// Which VMs are accelerated: walk each proxy to its VIF to its VM.
		accelerated := map[xenapi.VMRef]bool{}
		for _, proxyRef := range site.Proxies {
			proxy, err := xenapi.PVSProxy.GetRecord(session, proxyRef)
			check(err)
			vif, err := xenapi.VIF.GetRecord(session, proxy.VIF)
			check(err)
			accelerated[vif.VM] = true
		}
		vms, err := xenapi.VM.GetAllRecords(session)
		check(err)
		total, count := 0, 0
		for ref, v := range vms {
			if v.IsControlDomain || v.IsATemplate || v.IsASnapshot {
				continue
			}
			total++
			if accelerated[ref] {
				count++
			}
		}
		fmt.Printf("  %d of %d VM(s) accelerated\n", count, total)
	}
	fmt.Println("OK: pvs-accelerator")
}
