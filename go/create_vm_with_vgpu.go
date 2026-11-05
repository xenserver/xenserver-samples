package main

import (
	"fmt"

	"go/xenapi"
)

// createVMWithVgpu - Create a VM with a vGPU.
//
// Provision a VM from a template and assign it a virtual GPU: find a GPU group that offers a vGPU
// type, attach it, and read the assignment back.
//
// Run it:
//
//	createVMWithVgpu("https://xenserver", "root", password, "Rocky Linux 8", "sdk-example-vgpu-vm")
func createVMWithVgpu(url, user, password, templateName, newVMName string) {
	session := connect(url, user, password)
	// Find a GPU group that offers a real (non-passthrough) vGPU type, plus that type.
	groupRef, typeRef := gpuGroupWithVgpuType(session)
	typeRec, err := xenapi.VGPUType.GetRecord(session, typeRef)
	check(err)
	fmt.Printf("Using vGPU type: %s (%d MB framebuffer)\n", typeRec.ModelName, typeRec.FramebufferSize/(1024*1024))

	// Provision a fresh VM from the template to attach the vGPU to.
	vmRef, err := xenapi.VM.Clone(session, templateByName(session, templateName), newVMName)
	check(err)
	provision(session, vmRef)

	// Assign the vGPU: device "0" is the VM's first vGPU slot, other_config is empty.
	vgpuRef, err := xenapi.VGPU.Create(session, vmRef, groupRef, "0", map[string]string{}, typeRef)
	check(err)
	uuid, _ := xenapi.VGPU.GetUUID(session, vgpuRef)
	fmt.Printf("Created vGPU: %s\n", uuid)

	// Read the assignment back.
	vgpus, _ := xenapi.VM.GetVGPUs(session, vmRef)
	assignedType, _ := xenapi.VGPU.GetType(session, vgpus[0])
	assigned, _ := xenapi.VGPUType.GetModelName(session, assignedType)
	fmt.Printf("VM now has %d vGPU(s); type = %s\n", len(vgpus), assigned)

	// Tidy up so the example is repeatable.
	check(xenapi.VGPU.Destroy(session, vgpuRef))
	destroyVMAndDisks(session, vmRef)
	fmt.Println("Cleaned up the example VM and its vGPU.")

	fmt.Println("OK: create-vm-with-vgpu")
	session.Logout()
}

// gpuGroupWithVgpuType finds a (GPU_group, VGPU_type) pair where the group offers a non-passthrough type.
func gpuGroupWithVgpuType(session *xenapi.Session) (xenapi.GPUGroupRef, xenapi.VGPUTypeRef) {
	groups, err := xenapi.GPUGroup.GetAllRecords(session)
	check(err)
	for ref, r := range groups {
		if len(r.PGPUs) == 0 {
			continue
		}
		for _, typeRef := range r.SupportedVGPUTypes {
			model, _ := xenapi.VGPUType.GetModelName(session, typeRef)
			if model != "passthrough" {
				return ref, typeRef
			}
		}
	}
	panic("no GPU group offers a vGPU type")
}
