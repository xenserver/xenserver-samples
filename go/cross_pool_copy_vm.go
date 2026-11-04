package main

import (
	"fmt"

	"go/xenapi"
)

// crossPoolCopyVM - Cross-pool copy a VM.
//
// Copy a VM from one pool to another: open a session to each pool, obtain a receiver token on the
// destination, then send a copy of the VM from the source. Takes the destination pool's URL as an
// extra argument after the password.
//
// Copy a VM from one pool to another (Storage XenMotion copy): get a receiver token from the
// destination with host.migrate_receive, then VM.migrate_send with copy=true on the source.
//
// Run it:
//
//	crossPoolCopyVM("https://poolA", "root", password, "https://poolB", "db-01", "", "")
func crossPoolCopyVM(url, user, password, destURL, vmName, destUser, destPassword string) {
	source := connect(url, user, password)
	if destUser == "" {
		destUser, destPassword = user, password
	}
	dest := connect(destURL, destUser, destPassword)
	// Destination: choose a host, network and SR, then ask for a receiver token. The disks go to
	// the destination pool's default SR and the data travels over the host's management network -
	// one both pools can certainly reach (the first network listed may well not be).
	destPools, err := xenapi.Pool.GetAll(dest)
	check(err)
	destHost, err := xenapi.Pool.GetMaster(dest, destPools[0])
	check(err)
	destSr, err := xenapi.Pool.GetDefaultSR(dest, destPools[0])
	check(err)
	pifs, err := xenapi.Host.GetPIFs(dest, destHost)
	check(err)
	var destNetwork xenapi.NetworkRef
	for _, pif := range pifs {
		if management, _ := xenapi.PIF.GetManagement(dest, pif); management {
			destNetwork, err = xenapi.PIF.GetNetwork(dest, pif)
			check(err)
		}
	}
	receiver, err := xenapi.Host.MigrateReceive(dest, destHost, destNetwork, map[string]string{})
	check(err)

	// Source: map every disk to the destination SR and every NIC to the destination network,
	// then send with copy=true (the source VM is left intact).
	vm := vmByName(source, vmName)
	vbds, _ := xenapi.VM.GetVBDs(source, vm)
	vdiMap := map[xenapi.VDIRef]xenapi.SRRef{}
	for _, vbd := range vbds {
		if t, _ := xenapi.VBD.GetType(source, vbd); t != xenapi.VbdTypeDisk {
			continue
		}
		vdi, _ := xenapi.VBD.GetVDI(source, vbd)
		vdiMap[vdi] = destSr
	}
	vifs, _ := xenapi.VM.GetVIFs(source, vm)
	vifMap := map[xenapi.VIFRef]xenapi.NetworkRef{}
	for _, vif := range vifs {
		vifMap[vif] = destNetwork
	}

	// MigrateSend8 is the 8-argument form every pool version accepts; MigrateSend itself takes newer
	// arguments that older hosts reject.
	copied, err := xenapi.VM.MigrateSend8(source, vm, receiver, false, vdiMap, vifMap,
		map[string]string{"copy": "true"}, map[xenapi.VGPURef]xenapi.GPUGroupRef{})
	check(err)
	fmt.Printf("Sent '%s' to the destination pool (copy); source still present: %v\n",
		vmName, vmByName(source, vmName) == vm)
	// The result is the new VM's ref on the DESTINATION pool - use the destination session to read it.
	copyName, err := xenapi.VM.GetNameLabel(dest, copied)
	check(err)
	copyUUID, err := xenapi.VM.GetUUID(dest, copied)
	check(err)
	fmt.Printf("  the copy on the destination: %s (%s)\n", copyName, copyUUID)

	// Tidy up so the example is repeatable: the copy and its disks, on the destination pool.
	destroyVMAndDisks(dest, copied)
	fmt.Println("OK: cross-pool-copy-vm")
	dest.Logout()
	source.Logout()
}
