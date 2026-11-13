package main

import (
	"fmt"
	"strings"

	"go/xenapi"
)

// gpuInventory - GPU inventory.
//
// Enumerate the pool's GPU groups, their physical GPUs and the vGPU types each offers.
//
// Run it:
//
//	gpuInventory("https://xenserver", "root", password)
func gpuInventory(url, user, password string) {
	session := connect(url, user, password)
	groups, err := xenapi.GPUGroup.GetAllRecords(session)
	check(err)
	fmt.Printf("GPU groups (%d):\n", len(groups))
	var firstGroup xenapi.GPUGroupRef
	haveGroup := false
	for ref, group := range groups {
		var types []string
		for _, t := range group.SupportedVGPUTypes {
			model, _ := xenapi.VGPUType.GetModelName(session, t)
			types = append(types, model)
		}
		fmt.Printf("  - %s: %d pGPU(s), vGPU types: %s\n",
			group.NameLabel, len(group.PGPUs), strings.Join(types, ", "))
		if !haveGroup {
			firstGroup, haveGroup = ref, true
		}
	}

	// How the pool spreads vGPUs across the physical GPUs in a group: depth-first packs each pGPU full
	// before using the next, breadth-first spreads them out.
	before, err := xenapi.GPUGroup.GetAllocationAlgorithm(session, firstGroup)
	check(err)
	check(xenapi.GPUGroup.SetAllocationAlgorithm(session, firstGroup, xenapi.AllocationAlgorithmBreadthFirst))
	after, _ := xenapi.GPUGroup.GetAllocationAlgorithm(session, firstGroup)
	fmt.Printf("Allocation:      %s -> %s\n", before, after)
	check(xenapi.GPUGroup.SetAllocationAlgorithm(session, firstGroup, before))

	fmt.Println("OK: gpu-inventory")
	session.Logout()
}
