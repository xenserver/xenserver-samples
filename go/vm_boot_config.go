package main

import (
	"fmt"

	"go/xenapi"
)

// vmBootConfig - VM boot configuration.
//
// Set a VM's vCPU counts and boot order, then read them back.
//
// Run it:
//
//	vmBootConfig("https://xenserver", "root", password, "Rocky Linux 8", "sdk-example-boot")
func vmBootConfig(url, user, password, templateName, newVMName string) {
	session := connect(url, user, password)
	vm, err := xenapi.VM.Clone(session, templateByName(session, templateName), newVMName)
	check(err)
	provision(session, vm)

	check(xenapi.VM.SetVCPUsMax(session, vm, 4))
	check(xenapi.VM.SetVCPUsAtStartup(session, vm, 2))

	// Boot mode: firmware ("bios"/"uefi") lives in HVM_boot_params; Secure Boot in
	// platform["secureboot"]. "auto" (not a hard-coded "true") is the real xe/XenCenter convention:
	// xapi resolves it against whether the pool actually holds Secure Boot certificates, at
	// VM.start time - a hard "true" would claim Secure Boot is on even on a template that was never
	// set up for it, since set_platform does no validation of its own.
	check(xenapi.VM.SetHVMBootParams(session, vm, map[string]string{"order": "cdn", "firmware": "uefi"}))
	platform, _ := xenapi.VM.GetPlatform(session, vm)
	platform["secureboot"] = "auto"
	check(xenapi.VM.SetPlatform(session, vm, platform))
	atStartup, _ := xenapi.VM.GetVCPUsAtStartup(session, vm)
	max, _ := xenapi.VM.GetVCPUsMax(session, vm)
	fmt.Printf("vCPUs: %d/%d\n", atStartup, max)
	bootParams, _ := xenapi.VM.GetHVMBootParams(session, vm)
	fmt.Printf("Boot order: %s\n", bootParams["order"])
	platform, _ = xenapi.VM.GetPlatform(session, vm)
	fmt.Printf("Boot mode: firmware=%s, secureboot=%s (resolved against pool certificates at boot)\n",
		bootParams["firmware"], platform["secureboot"])

	destroyVMAndDisks(session, vm)
	fmt.Println("OK: vm-boot-config")
	session.Logout()
}
