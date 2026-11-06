<!-- Generated from workflows.json, the example sources and a run of each example. Edit those, not this file. -->

# Workflow examples

Real-world pool-management tasks, each implemented in PowerShell, the xe CLI, Python, C# (.NET), Go and Java. Each page shows the code in every language and example output from running it against a test pool: on yours, the names, addresses and UUIDs will differ. Every program first opens a session: see [Connecting](connecting.md).

Run any of them with `<program> <workflow> <url> <user> <password> [key=value ...]`; see the [repository README](../../README.md) for how to build and run each language.

## Getting started

| Workflow | What it does |
|---|---|
| [Connect & inventory](connect-inventory.md) | Log in to a pool and take stock of it: read the pool name, enumerate the hosts and list the virtual machines with their power state. |
| [Look up an object by UUID](find-by-uuid.md) | Resolve a stable UUID back to a live object reference — how to persist a reference to an object across sessions. |
| [Drive an asynchronous task](wait-for-task.md) | Start a long-running operation asynchronously to get a task back immediately, then poll it to completion and read its result — how to drive operations without blocking. |
| [Handle an API error](error-handling.md) | Catch an API failure and inspect its error code and parameters — the shape of every error the API returns, and how to react to it robustly. |
| [Trace API calls](trace-api-calls.md) | Send a W3C trace context with your API calls, so the work the pool does for them is recorded as part of your application's distributed trace. |
| [Event monitoring](events.md) | Subscribe to the event stream and observe a change land as an event — the mechanism for keeping a client's view of the pool live. |

## Virtual machines

| Workflow | What it does |
|---|---|
| [Create a VM from a template](create-vm.md) | Clone one of the built-in templates and provision the clone into a real, installable VM. |
| [Create a VM (full workflow)](new-vm-wizard.md) | Create a VM end to end: pick a template, name the VM, choose an installation source and a home server, set CPU & memory, add a disk on a storage repository, attach a network interface and start it — the full sequence, rather than a single clone call. |
| [Clone a VM](clone-vm.md) | Make a fast copy-on-write clone of a VM on the same storage repository — distinct from a full copy — the quick way to stamp out new VMs from a halted "golden" image. |
| [Copy a VM](copy-vm.md) | Make a full, independent copy of a VM onto a chosen storage repository (a deep copy of its disks) — distinct from a fast, copy-on-write clone. |
| [Cross-pool copy a VM](cross-pool-copy-vm.md) | Copy a VM from one pool to another: open a session to each pool, obtain a receiver token on the destination, then send a copy of the VM from the source. |
| [Delete a VM](delete-vm.md) | Remove a VM and its owned disks: deleting a VM leaves its disks behind, so the disks are destroyed explicitly afterward. |
| [Manage VM groups](manage-vm-groups.md) | Create an anti-affinity VM group, put a VM in it, read the membership back from the group side, then take the VM out again and delete the group. |
| [Snapshot schedule](snapshot-schedule.md) | Create a scheduled-snapshot policy, attach a VM to it, run it on demand (the xe CLI version only creates and removes the schedule) and watch the retention limit prune the oldest snapshot away. |
| [Manage VM disks](manage-vm-disks.md) | Deactivate a running VM's disk, resize it, reactivate it — the Activate/Deactivate and Resize operations from the VM's Storage tab. |
| [VM power lifecycle](vm-lifecycle.md) | Drive a VM through its power states — start it, suspend it to memory, resume it and shut it down cleanly. |
| [Snapshot & revert](snapshot-revert.md) | Take a snapshot of a VM and then revert the VM back to that point-in-time, as you would before a risky change. |
| [Checkpoint & revert](checkpoint-vm.md) | Take a checkpoint of a running VM (disk AND memory, unlike a plain snapshot) and revert to it, as you would before a risky in-guest change. |
| [Convert a VM to a template](convert-to-template.md) | Turn a VM into a reusable custom template. |
| [Edit VM properties](edit-vm-properties.md) | Change a VM's description and custom metadata, then read the changes back. |
| [VM boot configuration](vm-boot-config.md) | Set a VM's vCPU counts and boot order, then read them back. |
| [Rename an object](rename-object.md) | Change an object's name and read it back — how any object is renamed. |
| [Create a VM with a vGPU](create-vm-with-vgpu.md) | Provision a VM from a template and assign it a virtual GPU: find a GPU group that offers a vGPU type, attach it, and read the assignment back. |
| [Get a VM's IP address](vm-ip-address.md) | Read a running VM's IP address from its guest metrics, as reported by the in-guest agent. |
| [List templates](list-templates.md) | Enumerate the pool's VM templates, both built-in and custom. |
| [Manage a virtual TPM](manage-vtpm.md) | Attach a virtual TPM to a halted VM, read it back and remove it again. |
| [Export and import a VM](export-import-vm.md) | Export a VM to an XVA file and import it back as a new one. |
| [Configure dynamic memory](configure-dynamic-memory.md) | Give a VM a dynamic memory range so the host can reclaim memory from it under pressure, and see the ordering rule the four bounds must obey enforced. |
| [Manage a VM's CD drive](manage-vm-media.md) | Add a DVD drive to a VM, insert an ISO from the library and eject it again. |
| [Create a VM and a template from a snapshot](vm-from-snapshot.md) | Turn a snapshot into a new VM that stands on its own, and into a reusable custom template. |
| [Manage a vApp](manage-vapp.md) | Group VMs into an appliance that starts and stops together in a defined order, start and shut it down as a unit, then remove it. |
| [Attach a USB device to a VM](attach-usb-device.md) | List the USB devices a host exposes, enable passthrough on one, attach it to a VM and detach it again. |

## Migration

| Workflow | What it does |
|---|---|
| [Live migrate a VM](live-migrate.md) | Move a running VM to another host in the pool with no downtime: check the destination can boot it, live-migrate it and confirm where it now runs. |
| [Storage live-migration](storage-migrate.md) | Move a running VM's virtual disk to a different storage repository while the VM keeps running — live storage migration. |

## Storage

| Workflow | What it does |
|---|---|
| [Create an NFS SR](create-nfs-sr.md) | Create a shared NFS storage repository on an NFS export (nfs_server, nfs_path), then detach and forget it. |
| [Create an iSCSI SR](create-iscsi-sr.md) | Connect a storage repository to a LUN on an iSCSI target, discovering the target's IQNs and then the LUNs behind one, as the New SR wizard does. |
| [Create an SMB SR](create-smb-sr.md) | Connect a shared storage repository to an SMB/CIFS file share, passing the server, share path and credentials (the password as a secret, never in plain text). |
| [Create an HBA SR](create-hba-sr.md) | Connect a shared storage repository to a fibre-channel (HBA) LUN: discover the LUNs the host can see with a deliberately failing probe, then create the SR by SCSI ID. |
| [Create an ISO library SR](create-iso-sr.md) | Connect an ISO-library storage repository to a file share of ISO images (here an NFS export), so the images are available as installation media. |
| [Attach a new disk](attach-disk.md) | Create a fresh virtual disk on a storage repository and attach it to a VM. |
| [Inventory a VM's disks](vbd-inventory.md) | List a VM's attached disks and the size of each. |
| [Storage repository usage](sr-usage.md) | Report each storage repository's used and total capacity, and rescan one. |
| [Reclaim freed space on a thin SR](reclaim-space.md) | Reclaim space freed by deleted disks on a thin-provisioned storage repository: find a trim-capable SR, pick a host with a live connection to it, and run the trim operation. |
| [Detach, reattach and forget storage](manage-sr-lifecycle.md) | Take a storage repository offline and bring it back: disconnect it from every host, reconnect and rescan it, then disconnect it once more and forget it for good. |
| [Point an SR at moved storage](reconnect-sr-storage.md) | When the storage behind an SR moves to a new address, point the SR at it: a host's connection to an SR cannot be edited, so unplug each one, recreate it with the new settings and plug it back. |
| [Copy a disk's contents](export-import-vdi.md) | Upload data into a virtual disk, download the disk's raw contents and copy them into a second disk, then check that the copy matches. |
| [Set the pool's default storage](set-default-sr.md) | Choose where the pool puts new disks, suspended VMs' memory images and host crash dumps by default, then put the original choice back. |
| [Attach an existing disk to another VM](attach-existing-disk.md) | Move a disk between VMs by detaching and re-attaching it, without copying the data. |
| [Back up with changed block tracking](changed-block-tracking.md) | Walk an incremental backup: turn on changed block tracking, snapshot twice, ask the server which blocks differ, then release the older snapshot's data while keeping the change metadata the next incremental needs. |

## Networking

| Workflow | What it does |
|---|---|
| [Create a network](create-network.md) | Create an internal network — an isolated virtual switch with no physical NIC — for VMs to talk to each other privately. |
| [List networks](list-networks.md) | Enumerate the pool's networks with their physical and virtual interface counts. |
| [Manage network interfaces](manage-vif.md) | Attach a virtual network interface to a VM and remove it again. |
| [Create a NIC bond](create-bond.md) | Bond two spare network interfaces onto a new network for redundancy and throughput, read the bond back, then dissolve it. |

## Hosts & pools

| Workflow | What it does |
|---|---|
| [Host information](host-info.md) | Read a host's software version, edition and CPU topology (sockets and cores). |
| [Enter & exit maintenance mode](host-maintenance.md) | Put a host into maintenance mode: disable it so it accepts no new VMs, evacuate its running guests to another host in the pool, then re-enable it. |
| [Read host & VM metrics](read-metrics.md) | Read live host metrics (total/free memory, liveness) and VM metrics (vCPU count, memory). |
| [Read RRD performance metrics](rrd-metrics.md) | Pull recent host performance samples from the RRD archives over the performance-data HTTP API, parse the legends and data, and summarise a metric (here the peak PVS Accelerator cache-space utilisation per host). |
| [Pool properties](pool-properties.md) | Read the pool name and default storage repository, then rename the pool and restore it. |
| [Configure high availability](configure-ha.md) | Turn on pool High Availability: choose a shared SR as the heartbeat statefile, compute how many host failures the pool can tolerate, enable HA, then disable it again. |
| [Raise and dismiss alerts](dismiss-alerts.md) | List the pool's alerts, then dismiss one — what the Notifications view does. |
| [Configure host power on](host-power-on.md) | Set a host's out-of-band power-on mode and credentials, then read them back. |
| [Rotate the pool secret](rotate-pool-secret.md) | Rotate the shared secret that authenticates pool members to each other. |
| [Manage TLS certificates](manage-certificates.md) | Install a pool-wide CA certificate, reset a host's server certificate, read the resulting fingerprints back, and turn on verification of the certificates members present to each other. |
| [Change the root password](change-root-password.md) | Change the local superuser password to a temporary one and back again, noting that a root session's old password is not checked. |
| [GPU inventory](gpu-inventory.md) | Enumerate the pool's GPU groups, their physical GPUs and the vGPU types each offers. |
| [PVS Accelerator inventory](pvs-accelerator.md) | Document a pool's Citrix Provisioning (PVS) Accelerator setup: each site's read cache (host, size, storage), its PVS servers (addresses and streaming port range), and which VMs are accelerated versus the whole pool. |
| [Configure PVS Accelerator](configure-pvs-accelerator.md) | Build a PVS Accelerator site from nothing and take it down again: introduce the site and a PVS server, put a read cache on each host's local storage, accelerate a VM by proxying its first NIC, then remove the proxy and the server and forget the site, which removes its cache storage. |
| [Configure NRPE monitoring](configure-nrpe.md) | Configure a host's NRPE (Nagios Remote Plugin Executor) agent through the monitoring plugin: read its status and configuration, enable it and permit a monitoring host, then read it back. |
| [Configure SNMP monitoring](configure-snmp.md) | Configure a host's SNMP agent through the monitoring plugin: read its configuration, enable it with a community string, then read the configuration and running status back. |
| [Manage SSH access](manage-ssh-access.md) | Open the pool's SSH service with an automatic cut-off, read back when it lapses, then close it again — the pool-level call fans out to every host. |
| [Change control domain memory](control-domain-memory.md) | Read and change a host's control domain (dom0) memory, then put it back. |
| [Back up a host's configuration](backup-host-config.md) | Download a host's configuration backup and hand it back as a restore would — and watch another host's backup be refused. |
| [Collect a server status report](server-status-report.md) | Gather a host's diagnostic bundle: read the catalogue of sections it can report on, download the whole bundle, then download a smaller one covering only the sections you pick. |
| [Restart a host](restart-host.md) | Take a host down and bring it back: stop it accepting new VMs, move the ones it is running elsewhere, reboot it, then power it right off and back on again. |
| [Clear a host's crash dumps](manage-crash-dumps.md) | Find the crash dumps a host kept after a failure, report how big and how old they are, then delete them to free the space. |
| [Configure pool options](configure-pool-options.md) | Read and change the pool-wide options that govern how it behaves — live patching, IGMP snooping and memory-migration compression — then put them back. |
| [Configure console access](configure-console-access.md) | Tighten how consoles and management traffic may be used: idle timeouts for the pool's own consoles and for VM consoles, one session at a time, and refusing plain HTTP. |
| [Configure host storage](configure-host-storage.md) | Set a host's iSCSI initiator name and turn on storage multipathing, then restore both. |
| [Send logs to a remote syslog server](configure-syslog.md) | Point a host's logs at a remote syslog server — and reconfigure the daemon, without which the setting is recorded but nothing changes. |
| [Manage device driver variants](manage-driver-variants.md) | Inspect a host's device drivers and choose which variant of one to use, seeing the difference between the variant that is selected and the one currently loaded. |
| [Manage pool membership](manage-pool-membership.md) | List the pool's member hosts and which one coordinates it, promote a different host to coordinator, then promote the original back. |
| [Configure clustering](configure-clustering.md) | Enable the clustering layer that shared block storage needs for thin provisioning, then watch quorum as a host leaves the cluster and rejoins it. |
| [Read workload-balancing recommendations](wlb-recommendations.md) | Point the pool at a workload-balancing appliance, read its placement recommendations for the pool and for one VM, then disconnect it. |

## Updates

| Workflow | What it does |
|---|---|
| [Configure updates (CDN)](configure-updates.md) | Point the pool at a CDN update repository and turn on automatic update sync: register a repository, set it as the pool's repository, enable update sync, read it back, then tidy up. |
| [Configure updates for an air-gapped pool](configure-offline-updates.md) | Switch a pool with no internet access to offline updates: make an update bundle repository the pool's only repository, upload an update bundle (.xsbundle) to it if you have one, list the updates it makes available, then tidy up. |
| [Apply updates from the CDN](apply-update.md) | Sync the pool's update metadata from the CDN and apply it to every host, then read each host's post-update reboot guidance. |
| [Rolling pool update](rolling-pool-update.md) | Apply the CDN's updates across the pool host by host, coordinator first: sync the metadata, then for each host apply the updates, moving its VMs to the rest of the pool and rebooting it only when the update requires, so the VMs keep running. |

## Organization & metadata

| Workflow | What it does |
|---|---|
| [Tag and organize objects](tags-and-folders.md) | Organize a pool with tags and folders: add tags to a VM and a host (tags work on any object type), place the VM in a folder, read it all back, then tidy up. |
| [Tag the pool](pool-tags.md) | Add and remove a tag on the pool itself, showing that tags apply to the pool, not just VMs and hosts. |
| [Custom fields](custom-fields.md) | Attach and read custom name/value fields on a VM — arbitrary metadata you define, stored on the object. |

## Security & access

| Workflow | What it does |
|---|---|
| [Manage Active Directory users](manage-ad-users.md) | Join the pool to an Active Directory domain, grant an AD user access with an RBAC role, read it back, then tidy up. |
| [List RBAC roles](list-roles.md) | Enumerate the pool's role-based access control (RBAC) roles — the roles that can be granted to users. |
| [Manage Secure Boot certificates](manage-secureboot-certificates.md) | Check whether the pool can supply UEFI Secure Boot certificates and whether a guest is ready to use them, then flag a guest whose certificates have gone stale for a refresh at its next boot — and unflag it again. |

## Disaster recovery

| Workflow | What it does |
|---|---|
| [Configure disaster recovery](configure-disaster-recovery.md) | Replicate the pool's metadata (the configuration of its VMs and vApps) to an iSCSI or Fibre Channel SR, so that a pool at a disaster recovery site can recover the VMs from the storage array's replica of that SR. |
| [Fail over to a disaster recovery site](disaster-recovery-failover.md) | On the pool at the disaster recovery site, attach the storage array's replica of the protected pool's storage, read the pool metadata replicated to it, and recover the VMs and vApps it describes. |

## Source files

Where every workflow above lives, per language:

- PowerShell: [`powershell/`](../../powershell) (one file per workflow)
- xe CLI: [`cli/`](../../cli) (one file per workflow)
- Python: [`python/`](../../python) (one file per workflow)
- C# (.NET): [`csharp/`](../../csharp) (one file per workflow)
- Go: [`go/`](../../go) (one file per workflow)
- Java: [`java/`](../../java) (one file per workflow)
