package main

import (
	"fmt"
	"sort"

	"go/xenapi"
)

// manageDriverVariants - Manage device driver variants.
//
// Inspect a host's device drivers and choose which variant of one to use, seeing the difference
// between the variant that is selected and the one currently loaded.
//
// A driver can ship in several variants - a vendor build alongside the one in the distribution, say.
// One is SELECTED (what the host will load) and one is ACTIVE (what it has loaded); they differ
// until the host reboots, which is what makes selecting a variant a scheduled change rather than an
// immediate one.
func manageDriverVariants(url, user, password string) {
	session := connect(url, user, password)
	defer session.Logout()

	pools, err := xenapi.Pool.GetAll(session)
	check(err)
	host, err := xenapi.Pool.GetMaster(session, pools[0])
	check(err)
	hostName, err := xenapi.Host.GetNameLabel(session, host)
	check(err)

	all, err := xenapi.HostDriver.GetAllRecords(session)
	check(err)
	drivers := map[xenapi.HostDriverRef]xenapi.HostDriverRecord{}
	var refs []xenapi.HostDriverRef
	for ref, r := range all {
		if r.Host != host {
			continue
		}
		drivers[ref] = r
		refs = append(refs, ref)
	}
	fmt.Printf("%s has %d driver(s)\n", hostName, len(refs))

	sort.Slice(refs, func(i, j int) bool { return drivers[refs[i]].Name < drivers[refs[j]].Name })
	shown := refs
	if len(shown) > 3 {
		shown = shown[:3]
	}
	for _, ref := range shown {
		d := drivers[ref]
		fmt.Printf("  %-14s %-10s %d variant(s), active=%s\n",
			d.Name, d.Type, len(d.Variants), variantName(session, d.ActiveVariant))
	}

	// Select a variant explicitly. It becomes the selected one immediately; whether it is also active
	// depends on whether the hardware is present and the driver already loaded.
	// Host_driver.select refuses a variant whose hardware isn't present (HOST_DRIVER_NO_HARDWARE) -
	// and a host lists drivers for plenty of devices it doesn't have - so pick a driver for hardware
	// this host actually has, and one of its variants that is usable.
	var chosenDriver xenapi.HostDriverRef
	var chosenVariant xenapi.DriverVariantRef
	found := false
	for _, ref := range refs {
		for _, v := range drivers[ref].Variants {
			if present, _ := xenapi.DriverVariant.GetHardwarePresent(session, v); present {
				chosenDriver, chosenVariant, found = ref, v, true
				break
			}
		}
		if found {
			break
		}
	}
	if !found {
		panic(fmt.Sprintf("no driver on %s has a variant for hardware it has", hostName))
	}
	check(xenapi.HostDriver.Select(session, chosenDriver, chosenVariant))
	after, err := xenapi.HostDriver.GetRecord(session, chosenDriver)
	check(err)
	fmt.Printf("  %s: selected %s, active %s\n",
		after.Name, variantName(session, after.SelectedVariant), variantName(session, after.ActiveVariant))

	fmt.Println("OK: manage-driver-variants")
}

// variantName is a driver variant's name, tolerating the null reference an unloaded driver has.
func variantName(session *xenapi.Session, ref xenapi.DriverVariantRef) string {
	if ref == "" || ref == "OpaqueRef:NULL" {
		return "(none)"
	}
	name, err := xenapi.DriverVariant.GetName(session, ref)
	check(err)
	return name
}
