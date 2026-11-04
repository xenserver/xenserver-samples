// XenServer Go SDK - real-world workflow examples.
//
// Each example mirrors a task you would perform in XenCenter, driven through the XenServer
// Management API (XenAPI). The Go binding speaks JSON-RPC and skips certificate validation
// by default for https URLs, which suits a host with a self-signed certificate.
//
// Each workflow is a function in a file of its own (connect_inventory.go, create_vm.go, ...). It takes
// the connection details (and any object it acts on, looked up by name) as parameters, opens its own
// session and logs out when done, so you can copy one into your own code along with connection.go (and
// any helper from helpers.go it uses); its doc comment shows the call. This file is only the
// command-line dispatcher, which lets one program run any of them.
//
// Usage:
//
//	go run . <workflow> <url> <username> <password>
//
//	<workflow>  any workflow id from the dispatcher (see also README.md)
package main

import (
	"fmt"
	"os"
	"strings"
)

// workflow pairs a workflow's dispatcher's placeholder defaults with the function that resolves a
// merged parameter set into a call - the Go equivalent of Python's `_wf(fn, **defaults)` wrapper.
type workflow struct {
	defaults map[string]string
	run      func(url, user, password string, params map[string]string)
}

// wf builds a workflow entry: defaults, merged with CLI-supplied overrides (see main), are handed
// to fn as one resolved parameter map.
func wf(defaults map[string]string, fn func(url, user, password string, params map[string]string)) workflow {
	return workflow{defaults: defaults, run: fn}
}

var workflows = map[string]workflow{
	"connect-inventory": wf(nil, func(u, n, p string, m map[string]string) { connectInventory(u, n, p) }),
	"create-vm": wf(map[string]string{"template_name": "Rocky Linux 8", "new_vm_name": "sdk-example-vm"},
		func(u, n, p string, m map[string]string) { createVM(u, n, p, m["template_name"], m["new_vm_name"]) }),
	"vm-lifecycle": wf(map[string]string{"source_vm": "web-01", "new_vm_name": "sdk-example-lifecycle"},
		func(u, n, p string, m map[string]string) { vmLifecycle(u, n, p, m["source_vm"], m["new_vm_name"]) }),
	"manage-vm-disks": wf(map[string]string{
		"source_vm": "web-01", "sr_name": "Shared NFS", "new_vm_name": "sdk-example-vm-disks",
	}, func(u, n, p string, m map[string]string) {
		manageVMDisks(u, n, p, m["source_vm"], m["sr_name"], m["new_vm_name"])
	}),
	"dismiss-alerts":       wf(nil, func(u, n, p string, m map[string]string) { dismissAlerts(u, n, p) }),
	"host-power-on":        wf(nil, func(u, n, p string, m map[string]string) { hostPowerOn(u, n, p) }),
	"rotate-pool-secret":   wf(nil, func(u, n, p string, m map[string]string) { rotatePoolSecret(u, n, p) }),
	"change-root-password": wf(nil, func(u, n, p string, m map[string]string) { changeRootPassword(u, n, p) }),
	"manage-certificates":  wf(nil, func(u, n, p string, m map[string]string) { manageCertificates(u, n, p) }),
	"snapshot-schedule": wf(map[string]string{"vm_name": "web-01", "schedule_name": "sdk-example-schedule"},
		func(u, n, p string, m map[string]string) { snapshotSchedule(u, n, p, m["vm_name"], m["schedule_name"]) }),
	"manage-vm-groups": wf(map[string]string{"vm_name": "web-01", "group_name": "sdk-example-group"},
		func(u, n, p string, m map[string]string) { manageVMGroups(u, n, p, m["vm_name"], m["group_name"]) }),
	"snapshot-revert": wf(map[string]string{"vm_name": "web-01", "snapshot_name": "sdk-example-snapshot"},
		func(u, n, p string, m map[string]string) { snapshotRevert(u, n, p, m["vm_name"], m["snapshot_name"]) }),
	"create-nfs-sr": wf(map[string]string{
		"nfs_server": "192.0.2.10", "nfs_path": "/export/sdk", "sr_name": "sdk-example-nfs",
	}, func(u, n, p string, m map[string]string) {
		createNfsSR(u, n, p, m["nfs_server"], m["nfs_path"], m["sr_name"])
	}),
	"create-network": wf(map[string]string{"network_name": "sdk-example-net"},
		func(u, n, p string, m map[string]string) { createNetwork(u, n, p, m["network_name"]) }),
	"edit-vm-properties": wf(map[string]string{"vm_name": "web-01"},
		func(u, n, p string, m map[string]string) { editVMProperties(u, n, p, m["vm_name"]) }),
	"events": wf(map[string]string{"vm_name": "web-01"},
		func(u, n, p string, m map[string]string) { events(u, n, p, m["vm_name"]) }),
	"new-vm-wizard": wf(map[string]string{"template_name": "Rocky Linux 8", "new_vm_name": "wizard-vm"},
		func(u, n, p string, m map[string]string) { newVMWizard(u, n, p, m["template_name"], m["new_vm_name"]) }),
	"live-migrate": wf(map[string]string{
		"source_vm": "web-01", "sr_name": "Shared NFS", "new_vm_name": "sdk-example-migrate",
	}, func(u, n, p string, m map[string]string) {
		liveMigrate(u, n, p, m["source_vm"], m["sr_name"], m["new_vm_name"])
	}),
	"host-maintenance": wf(map[string]string{
		"source_vm": "web-01", "sr_name": "Shared NFS", "new_vm_name": "sdk-example-maint",
	}, func(u, n, p string, m map[string]string) {
		hostMaintenance(u, n, p, m["source_vm"], m["sr_name"], m["new_vm_name"])
	}),
	"configure-ha": wf(map[string]string{"heartbeat_sr_name": "Shared NFS"},
		func(u, n, p string, m map[string]string) { configureHa(u, n, p, m["heartbeat_sr_name"]) }),
	"copy-vm": wf(map[string]string{"vm_name": "db-01", "sr_name": "Shared NFS", "copy_name": "sdk-example-copy"},
		func(u, n, p string, m map[string]string) { copyVM(u, n, p, m["vm_name"], m["sr_name"], m["copy_name"]) }),
	"create-vm-with-vgpu": wf(map[string]string{"template_name": "Rocky Linux 8", "new_vm_name": "sdk-example-vgpu-vm"},
		func(u, n, p string, m map[string]string) {
			createVMWithVgpu(u, n, p, m["template_name"], m["new_vm_name"])
		}),
	"tags-and-folders": wf(map[string]string{"vm_name": "web-01"},
		func(u, n, p string, m map[string]string) { tagsAndFolders(u, n, p, m["vm_name"]) }),
	"configure-updates": wf(map[string]string{
		"repo_url": "https://repo.ops.xenserver.com/xs9", "source_url": "https://repo-src.ops.xenserver.com/xs9",
	}, func(u, n, p string, m map[string]string) { configureUpdates(u, n, p, m["repo_url"], m["source_url"]) }),
	"clone-vm": wf(map[string]string{"vm_name": "db-01", "clone_name": "sdk-example-clone"},
		func(u, n, p string, m map[string]string) { cloneVM(u, n, p, m["vm_name"], m["clone_name"]) }),
	"delete-vm": wf(map[string]string{"template_name": "Rocky Linux 8", "new_vm_name": "sdk-example-delete"},
		func(u, n, p string, m map[string]string) { deleteVM(u, n, p, m["template_name"], m["new_vm_name"]) }),
	"storage-migrate": wf(map[string]string{"source_vm": "web-01", "new_vm_name": "sdk-example-storagemigrate"},
		func(u, n, p string, m map[string]string) {
			storageMigrate(u, n, p, m["source_vm"], m["new_vm_name"])
		}),
	"apply-update": wf(map[string]string{
		"repo_url": "https://repo.ops.xenserver.com/xs9", "source_url": "https://repo-src.ops.xenserver.com/xs9",
	}, func(u, n, p string, m map[string]string) { applyUpdate(u, n, p, m["repo_url"], m["source_url"]) }),
	"checkpoint-vm": wf(map[string]string{"source_vm": "web-01", "new_vm_name": "sdk-example-checkpoint"},
		func(u, n, p string, m map[string]string) { checkpointVM(u, n, p, m["source_vm"], m["new_vm_name"]) }),
	"attach-disk": wf(map[string]string{
		"template_name": "Rocky Linux 8", "sr_name": "Shared NFS", "new_vm_name": "sdk-example-attachdisk",
	}, func(u, n, p string, m map[string]string) {
		attachDisk(u, n, p, m["template_name"], m["sr_name"], m["new_vm_name"])
	}),
	"wait-for-task": wf(map[string]string{"template_name": "Rocky Linux 8", "new_vm_name": "sdk-example-asynctask"},
		func(u, n, p string, m map[string]string) { waitForTask(u, n, p, m["template_name"], m["new_vm_name"]) }),
	"error-handling":  wf(nil, func(u, n, p string, m map[string]string) { errorHandling(u, n, p) }),
	"trace-api-calls": wf(nil, func(u, n, p string, m map[string]string) { traceAPICalls(u, n, p) }),
	"list-templates":  wf(nil, func(u, n, p string, m map[string]string) { listTemplates(u, n, p) }),
	"custom-fields": wf(map[string]string{"vm_name": "web-01"},
		func(u, n, p string, m map[string]string) { customFields(u, n, p, m["vm_name"]) }),
	"gpu-inventory": wf(nil, func(u, n, p string, m map[string]string) { gpuInventory(u, n, p) }),
	"read-metrics":  wf(nil, func(u, n, p string, m map[string]string) { readMetrics(u, n, p) }),
	"rename-object": wf(map[string]string{"vm_name": "web-01"},
		func(u, n, p string, m map[string]string) { renameObject(u, n, p, m["vm_name"]) }),
	"vm-boot-config": wf(map[string]string{"template_name": "Rocky Linux 8", "new_vm_name": "sdk-example-boot"},
		func(u, n, p string, m map[string]string) { vmBootConfig(u, n, p, m["template_name"], m["new_vm_name"]) }),
	"host-info":       wf(nil, func(u, n, p string, m map[string]string) { hostInfo(u, n, p) }),
	"list-roles":      wf(nil, func(u, n, p string, m map[string]string) { listRoles(u, n, p) }),
	"pool-properties": wf(nil, func(u, n, p string, m map[string]string) { poolProperties(u, n, p) }),
	"sr-usage":        wf(nil, func(u, n, p string, m map[string]string) { srUsage(u, n, p) }),
	"manage-vif": wf(map[string]string{"template_name": "Rocky Linux 8", "new_vm_name": "sdk-example-vif"},
		func(u, n, p string, m map[string]string) { manageVif(u, n, p, m["template_name"], m["new_vm_name"]) }),
	"list-networks": wf(nil, func(u, n, p string, m map[string]string) { listNetworks(u, n, p) }),
	"vbd-inventory": wf(map[string]string{"vm_name": "db-01"},
		func(u, n, p string, m map[string]string) { vbdInventory(u, n, p, m["vm_name"]) }),
	"pool-tags": wf(nil, func(u, n, p string, m map[string]string) { poolTags(u, n, p) }),
	"convert-to-template": wf(map[string]string{"template_name": "Rocky Linux 8", "new_vm_name": "sdk-example-totemplate"},
		func(u, n, p string, m map[string]string) {
			convertToTemplate(u, n, p, m["template_name"], m["new_vm_name"])
		}),
	"find-by-uuid": wf(map[string]string{"vm_name": "web-01"},
		func(u, n, p string, m map[string]string) { findByUUID(u, n, p, m["vm_name"]) }),
	"rolling-pool-update": wf(map[string]string{
		"repo_url": "https://repo.ops.xenserver.com/xs9", "source_url": "https://repo-src.ops.xenserver.com/xs9",
	}, func(u, n, p string, m map[string]string) { rollingPoolUpdate(u, n, p, m["repo_url"], m["source_url"]) }),
	"pvs-accelerator": wf(nil, func(u, n, p string, m map[string]string) { pvsAccelerator(u, n, p) }),
	"configure-pvs-accelerator": wf(map[string]string{"vm_name": "db-01"},
		func(u, n, p string, m map[string]string) { configurePvsAccelerator(u, n, p, m["vm_name"]) }),
	"manage-ssh-access": wf(nil, func(u, n, p string, m map[string]string) { manageSSHAccess(u, n, p) }),
	"manage-vtpm":       wf(nil, func(u, n, p string, m map[string]string) { manageVtpm(u, n, p) }),
	"export-import-vm": wf(map[string]string{"vm_name": "db-01"},
		func(u, n, p string, m map[string]string) { exportImportVm(u, n, p, m["vm_name"]) }),
	"configure-dynamic-memory": wf(nil, func(u, n, p string, m map[string]string) { configureDynamicMemory(u, n, p) }),
	"manage-vm-media":          wf(nil, func(u, n, p string, m map[string]string) { manageVmMedia(u, n, p) }),
	"backup-host-config":       wf(nil, func(u, n, p string, m map[string]string) { backupHostConfig(u, n, p) }),
	"manage-sr-lifecycle": wf(map[string]string{"nfs_server": "192.0.2.10", "nfs_path": "/export/spare"},
		func(u, n, p string, m map[string]string) { manageSrLifecycle(u, n, p, m["nfs_server"], m["nfs_path"]) }),
	"reconnect-sr-storage": wf(map[string]string{"nfs_server": "192.0.2.10", "nfs_path": "/export/spare"},
		func(u, n, p string, m map[string]string) {
			reconnectSrStorage(u, n, p, m["nfs_server"], m["nfs_path"], m["new_nfs_server"])
		}),
	"export-import-vdi": wf(map[string]string{"sr_name": "Shared NFS"},
		func(u, n, p string, m map[string]string) { exportImportVdi(u, n, p, m["sr_name"]) }),
	"configure-offline-updates": wf(nil,
		func(u, n, p string, m map[string]string) { configureOfflineUpdates(u, n, p, m["bundle_path"]) }),
	"set-default-sr": wf(map[string]string{"nfs_server": "192.0.2.10", "nfs_path": "/export/spare"},
		func(u, n, p string, m map[string]string) { setDefaultSr(u, n, p, m["nfs_server"], m["nfs_path"]) }),
	"server-status-report": wf(nil, func(u, n, p string, m map[string]string) { serverStatusReport(u, n, p) }),
	// disaster-recovery has no usable default for dr_url (null/None/empty) - a second pool is
	// structurally required, so raise a clear error naming what's missing if it's not supplied.
	"disaster-recovery": wf(map[string]string{"dr_url": ""},
		func(u, n, p string, m map[string]string) { disasterRecovery(u, n, p, m["dr_url"]) }),
	"manage-secureboot-certificates": wf(nil, func(u, n, p string, m map[string]string) { manageSecurebootCertificates(u, n, p) }),
	"restart-host":                   wf(nil, func(u, n, p string, m map[string]string) { restartHost(u, n, p) }),
	"manage-crash-dumps":             wf(nil, func(u, n, p string, m map[string]string) { manageCrashDumps(u, n, p) }),
	"vm-from-snapshot": wf(map[string]string{"vm_name": "db-01"},
		func(u, n, p string, m map[string]string) { vmFromSnapshot(u, n, p, m["vm_name"]) }),
	"attach-existing-disk":   wf(nil, func(u, n, p string, m map[string]string) { attachExistingDisk(u, n, p) }),
	"changed-block-tracking": wf(nil, func(u, n, p string, m map[string]string) { changedBlockTracking(u, n, p) }),
	"control-domain-memory":  wf(nil, func(u, n, p string, m map[string]string) { controlDomainMemory(u, n, p) }),
	"rrd-metrics":            wf(nil, func(u, n, p string, m map[string]string) { rrdMetrics(u, n, p) }),
	"reclaim-space":          wf(nil, func(u, n, p string, m map[string]string) { reclaimSpace(u, n, p) }),
	"vm-ip-address": wf(map[string]string{"timeout": "60", "interval": "2"},
		func(u, n, p string, m map[string]string) { vmIpAddress(u, n, p, m["timeout"], m["interval"]) }),
	"manage-ad-users": wf(map[string]string{
		"domain": "", "admin_user": "alice", "admin_password": "Password1", "new_user": "alice",
		"ldaps": "false",
	}, func(u, n, p string, m map[string]string) {
		manageAdUsers(u, n, p, m["domain"], m["admin_user"], m["admin_password"], m["new_user"], m["ldaps"])
	}),
	"create-iscsi-sr": wf(map[string]string{
		"target": "192.0.2.30", "port": "", "chap_user": "", "chap_password": "", "target_iqn": "",
		"sr_name": "sdk-example-iscsi",
	}, func(u, n, p string, m map[string]string) {
		createIscsiSr(u, n, p, m["target"], m["port"], m["chap_user"], m["chap_password"], m["target_iqn"],
			m["sr_name"])
	}),
	"create-smb-sr": wf(map[string]string{
		"server": "192.0.2.40", "share": "/vmstore", "smb_username": "Administrator",
		"smb_password": "Password1", "sr_name": "sdk-example-smb",
	}, func(u, n, p string, m map[string]string) {
		createSmbSr(u, n, p, m["server"], m["share"], m["smb_username"], m["smb_password"], m["sr_name"])
	}),
	"create-hba-sr": wf(map[string]string{"scsi_id": "", "sr_name": "sdk-example-hba"},
		func(u, n, p string, m map[string]string) { createHbaSr(u, n, p, m["scsi_id"], m["sr_name"]) }),
	"create-iso-sr": wf(map[string]string{"location": "192.0.2.10:/isos"},
		func(u, n, p string, m map[string]string) { createIsoSr(u, n, p, m["location"]) }),
	"configure-nrpe": wf(nil, func(u, n, p string, m map[string]string) { configureNrpe(u, n, p) }),
	"configure-snmp": wf(map[string]string{"trap_destination": "192.0.2.50"},
		func(u, n, p string, m map[string]string) { configureSnmp(u, n, p, m["trap_destination"]) }),
	"configure-clustering":   wf(nil, func(u, n, p string, m map[string]string) { configureClustering(u, n, p) }),
	"manage-pool-membership": wf(nil, func(u, n, p string, m map[string]string) { managePoolMembership(u, n, p) }),
	"create-bond":            wf(nil, func(u, n, p string, m map[string]string) { createBond(u, n, p) }),
	"manage-vapp": wf(map[string]string{"vm_name": "db-01"},
		func(u, n, p string, m map[string]string) { manageVapp(u, n, p, m["vm_name"]) }),
	"attach-usb-device": wf(map[string]string{"vm_name": "web-01"},
		func(u, n, p string, m map[string]string) { attachUsbDevice(u, n, p, m["vm_name"]) }),
	"wlb-recommendations": wf(map[string]string{
		"vm_name": "web-01", "wlb_host_port": "wlb.example:8012", "wlb_username": "wlbuser", "wlb_password": "wlbpass",
		"wlb_certificate": "",
	}, func(u, n, p string, m map[string]string) {
		wlbRecommendations(u, n, p, m["vm_name"], m["wlb_host_port"], m["wlb_username"], m["wlb_password"],
			m["wlb_certificate"])
	}),
	"configure-pool-options":   wf(nil, func(u, n, p string, m map[string]string) { configurePoolOptions(u, n, p) }),
	"configure-console-access": wf(nil, func(u, n, p string, m map[string]string) { configureConsoleAccess(u, n, p) }),
	"configure-host-storage":   wf(nil, func(u, n, p string, m map[string]string) { configureHostStorage(u, n, p) }),
	"configure-syslog": wf(map[string]string{"syslog_server": "192.0.2.50"},
		func(u, n, p string, m map[string]string) { configureSyslog(u, n, p, m["syslog_server"]) }),
	"manage-driver-variants": wf(nil, func(u, n, p string, m map[string]string) { manageDriverVariants(u, n, p) }),
}

func main() {
	// cross-pool-copy-vm spans two pools, so it keeps its own positional form - the destination URL,
	// then optionally that pool's credentials (if they differ from the source's) and the VM to copy -
	// with no key=value overrides.
	if len(os.Args) >= 2 && os.Args[1] == "cross-pool-copy-vm" {
		n := len(os.Args)
		if n != 6 && n != 8 && n != 9 {
			fmt.Fprintln(os.Stderr, "usage: go run . cross-pool-copy-vm <sourceUrl> <user> <password> <destUrl>"+
				" [<destUser> <destPassword> [<vmName>]]")
			os.Exit(2)
		}
		vmName, destUser, destPassword := "db-01", "", ""
		if n >= 8 {
			destUser, destPassword = os.Args[6], os.Args[7]
		}
		if n == 9 {
			vmName = os.Args[8]
		}
		crossPoolCopyVM(os.Args[2], os.Args[3], os.Args[4], os.Args[5], vmName, destUser, destPassword)
		return
	}
	if len(os.Args) < 5 {
		fmt.Fprintln(os.Stderr, "usage: go run . <workflow> <url> <user> <password> [key=value ...]")
		os.Exit(2)
	}
	workflow, ok := workflows[os.Args[1]]
	if !ok {
		fmt.Fprintf(os.Stderr, "unknown workflow: %s\n", os.Args[1])
		os.Exit(2)
	}

	// Everything else is a named parameter with a placeholder default; key=value arguments
	// after the password override that workflow's default for the named parameter.
	params := make(map[string]string, len(workflow.defaults))
	for k, v := range workflow.defaults {
		params[k] = v
	}
	for _, arg := range os.Args[5:] {
		key, value, found := strings.Cut(arg, "=")
		if !found {
			fmt.Fprintf(os.Stderr, "extra arguments must be key=value (got %q)\n", arg)
			os.Exit(2)
		}
		params[key] = value
	}

	workflow.run(os.Args[2], os.Args[3], os.Args[4], params)
}
