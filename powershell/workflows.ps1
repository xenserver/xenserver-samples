<#
    XenServer PowerShell SDK - real-world workflow examples.

    Each example is a common administration task, driven through the XenServer
    PowerShell module (which wraps the XenAPI .NET binding and speaks JSON-RPC).

    Written in idiomatic PowerShell: the module's cmdlets take their object from the pipeline, so an
    example reads as a pipeline of verbs - fetch an object with Get-Xen*, then pipe it straight into the
    cmdlet that acts on it (Invoke-Xen* for actions, Set-Xen*/Add-Xen*/Remove-Xen*Property for edits,
    Remove-Xen* to delete). Long-running actions use the -Async -PassThru | Wait-XenTask -ShowProgress
    idiom, and a second pool is driven through the same cmdlets with -SessionOpaqueRef. Everything goes
    through the module's cmdlets - there are no raw XenAPI .NET static method calls. The one thing the
    module ships no cmdlet for is the event API, so the events example calls its JSON-RPC endpoint with
    Invoke-RestMethod (still pure PowerShell - Connect-Example has already established trust for the
    server's certificate).

    Each workflow is a function in a script of its own, in a folder per area (GettingStarted\,
    VirtualMachines\, Storage\, ...). It takes the connection details (and any object it operates on) as
    parameters, opens its own session, does its work and disconnects, so you can copy one into your own
    scripts along with Connection.ps1 (and any helper from Helpers.ps1 it uses); Get-Help shows what it
    does and how to call it. This script loads them all and is otherwise only the command-line
    dispatcher, which lets one program run any of them.

    Usage:
        powershell -File workflows.ps1 <workflow> <url> <username> <password>

        <workflow>  any workflow id from the dispatcher at the bottom (see also README.md)
#>
param(
    [Parameter(Mandatory = $true)][string]$Workflow,
    [Parameter(Mandatory = $true)][string]$Url,
    [Parameter(Mandatory = $true)][string]$UserName,
    [Parameter(Mandatory = $true)][string]$Password,
    # Anything a particular workflow needs beyond the connection. Only cross-pool-copy-vm uses it (for
    # the second pool's URL) and it reads it from the dispatcher at the bottom, so nothing up here has to
    # know about it.
    [Parameter(ValueFromRemainingArguments)][string[]]$WorkflowArgs
)

$ErrorActionPreference = "Stop"

# The SDK's compiled PowerShell module: copy XenServerPowerShell/PowerShell_51/XenServerPSModule (or
# PowerShell_7 for PowerShell 7) from the SDK into a folder on $env:PSModulePath.
Import-Module XenServerPSModule

# Load the connect helper, the shared helpers and every workflow function.
. (Join-Path $PSScriptRoot "Connection.ps1")
. (Join-Path $PSScriptRoot "Helpers.ps1")
foreach ($file in Get-ChildItem -Path $PSScriptRoot -Filter *.ps1 -Recurse |
        Where-Object { $_.DirectoryName -ne $PSScriptRoot }) {
    . $file.FullName
}

# --- entry point ----------------------------------------------------------------------- Maps the
# <workflow> argument to the matching workflow function, supplying the concrete objects each one operates
# on, plus a placeholder default for every other named parameter - the equivalent of Python's _wf(fn,
# **defaults) wrapper. The command line accepts key=value arguments after the password (captured in
# $WorkflowArgs above), overriding that workflow's default for the named parameter. In your own scripts you
# would call these functions directly (Get-Help <function> -Examples shows how) rather than through this
# dispatcher. cross-pool-copy-vm keeps its own positional form: the destination pool URL, then optionally
# that pool's credentials (if they differ from the source's) and the VM to copy.
if ($Workflow -eq "cross-pool-copy-vm") {
    if (-not $WorkflowArgs -or $WorkflowArgs.Count -notin 1, 3, 4) {
        Write-Error "usage: workflows.ps1 cross-pool-copy-vm <url> <user> <password> <destUrl> [<destUser> <destPassword> [<vmName>]]"
        exit 2
    }
    $copyArgs = @{ Url = $Url; UserName = $UserName; Password = $Password; DestUrl = $WorkflowArgs[0] }
    if ($WorkflowArgs.Count -ge 3) { $copyArgs.DestUserName = $WorkflowArgs[1]; $copyArgs.DestPassword = $WorkflowArgs[2] }
    if ($WorkflowArgs.Count -eq 4) { $copyArgs.VmName = $WorkflowArgs[3] }
    Invoke-CrossPoolCopyVm @copyArgs
    exit 0
}

$WORKFLOWS = @{
    "connect-inventory"              = @{ Function = "Invoke-ConnectInventory";             Defaults = @{} }
    "create-vm"                      = @{ Function = "Invoke-CreateVm";                     Defaults = @{ TemplateName = "Rocky Linux 8" } }
    "vm-lifecycle"                   = @{ Function = "Invoke-VmLifecycle";                  Defaults = @{ SourceVm = "web-01" } }
    "manage-vm-disks"                = @{ Function = "Invoke-ManageVmDisks";                Defaults = @{ SourceVm = "web-01"; SrName = "Shared NFS" } }
    "dismiss-alerts"                 = @{ Function = "Invoke-DismissAlerts";                Defaults = @{} }
    "host-power-on"                  = @{ Function = "Invoke-HostPowerOn";                  Defaults = @{} }
    "rotate-pool-secret"             = @{ Function = "Invoke-RotatePoolSecret";             Defaults = @{} }
    "change-root-password"           = @{ Function = "Invoke-ChangeRootPassword";           Defaults = @{} }
    "manage-certificates"            = @{ Function = "Invoke-ManageCertificates";           Defaults = @{} }
    "snapshot-schedule"              = @{ Function = "Invoke-SnapshotSchedule";             Defaults = @{ VmName = "web-01" } }
    "manage-vm-groups"               = @{ Function = "Invoke-ManageVmGroups";               Defaults = @{ VmName = "web-01" } }
    "snapshot-revert"                = @{ Function = "Invoke-SnapshotRevert";               Defaults = @{ VmName = "web-01" } }
    "create-nfs-sr"                  = @{ Function = "Invoke-CreateNfsSr";                  Defaults = @{ NfsServer = "192.0.2.10"; NfsPath = "/export/sdk" } }
    "create-network"                 = @{ Function = "Invoke-CreateNetwork";                Defaults = @{} }
    "edit-vm-properties"             = @{ Function = "Invoke-EditVmProperties";             Defaults = @{ VmName = "web-01" } }
    "events"                         = @{ Function = "Invoke-Events";                       Defaults = @{ VmName = "web-01" } }
    "new-vm-wizard"                  = @{ Function = "Invoke-NewVmWizard";                  Defaults = @{ TemplateName = "Rocky Linux 8" } }
    "live-migrate"                   = @{ Function = "Invoke-LiveMigrate";                  Defaults = @{ SourceVm = "web-01"; SrName = "Shared NFS" } }
    "host-maintenance"               = @{ Function = "Invoke-HostMaintenance";              Defaults = @{ SourceVm = "web-01"; SrName = "Shared NFS" } }
    "configure-ha"                   = @{ Function = "Invoke-ConfigureHa";                  Defaults = @{ HeartbeatSrName = "Shared NFS" } }
    "copy-vm"                        = @{ Function = "Invoke-CopyVm";                       Defaults = @{ VmName = "db-01"; SrName = "Shared NFS" } }
    "create-vm-with-vgpu"            = @{ Function = "Invoke-CreateVmWithVgpu";             Defaults = @{ TemplateName = "Rocky Linux 8" } }
    "tags-and-folders"               = @{ Function = "Invoke-TagsAndFolders";               Defaults = @{ VmName = "web-01" } }
    "configure-offline-updates"      = @{ Function = "Invoke-ConfigureOfflineUpdates";      Defaults = @{} }
    "configure-updates"              = @{ Function = "Invoke-ConfigureUpdates";             Defaults = @{ RepoUrl = "https://repo.ops.xenserver.com/xs9"; SourceUrl = "https://repo-src.ops.xenserver.com/xs9" } }
    "clone-vm"                       = @{ Function = "Invoke-CloneVm";                      Defaults = @{ VmName = "db-01" } }
    "delete-vm"                      = @{ Function = "Invoke-DeleteVm";                     Defaults = @{ TemplateName = "Rocky Linux 8" } }
    "storage-migrate"                = @{ Function = "Invoke-StorageMigrate";               Defaults = @{ SourceVm = "web-01" } }
    "apply-update"                   = @{ Function = "Invoke-ApplyUpdate";                  Defaults = @{ RepoUrl = "https://repo.ops.xenserver.com/xs9"; SourceUrl = "https://repo-src.ops.xenserver.com/xs9" } }
    "checkpoint-vm"                  = @{ Function = "Invoke-CheckpointVm";                 Defaults = @{ SourceVm = "web-01" } }
    "attach-disk"                    = @{ Function = "Invoke-AttachDisk";                   Defaults = @{ TemplateName = "Rocky Linux 8"; SrName = "Shared NFS" } }
    "wait-for-task"                  = @{ Function = "Invoke-WaitForTask";                  Defaults = @{ TemplateName = "Rocky Linux 8" } }
    "error-handling"                 = @{ Function = "Invoke-ErrorHandling";                Defaults = @{} }
    "trace-api-calls"                = @{ Function = "Invoke-TraceApiCalls";                Defaults = @{} }
    "list-templates"                 = @{ Function = "Invoke-ListTemplates";                Defaults = @{} }
    "custom-fields"                  = @{ Function = "Invoke-CustomFields";                 Defaults = @{ VmName = "web-01" } }
    "gpu-inventory"                  = @{ Function = "Invoke-GpuInventory";                 Defaults = @{} }
    "read-metrics"                   = @{ Function = "Invoke-ReadMetrics";                  Defaults = @{} }
    "rename-object"                  = @{ Function = "Invoke-RenameObject";                 Defaults = @{ VmName = "web-01" } }
    "vm-boot-config"                 = @{ Function = "Invoke-VmBootConfig";                 Defaults = @{ TemplateName = "Rocky Linux 8" } }
    "host-info"                      = @{ Function = "Invoke-HostInfo";                     Defaults = @{} }
    "list-roles"                     = @{ Function = "Invoke-ListRoles";                    Defaults = @{} }
    "pool-properties"                = @{ Function = "Invoke-PoolProperties";               Defaults = @{} }
    "sr-usage"                       = @{ Function = "Invoke-SrUsage";                      Defaults = @{} }
    "manage-vif"                     = @{ Function = "Invoke-ManageVif";                    Defaults = @{ TemplateName = "Rocky Linux 8" } }
    "list-networks"                  = @{ Function = "Invoke-ListNetworks";                 Defaults = @{} }
    "vbd-inventory"                  = @{ Function = "Invoke-VbdInventory";                 Defaults = @{ VmName = "db-01" } }
    "pool-tags"                      = @{ Function = "Invoke-PoolTags";                     Defaults = @{} }
    "convert-to-template"            = @{ Function = "Invoke-ConvertToTemplate";            Defaults = @{ TemplateName = "Rocky Linux 8" } }
    "find-by-uuid"                   = @{ Function = "Invoke-FindByUuid";                   Defaults = @{ VmName = "web-01" } }
    "rolling-pool-update"            = @{ Function = "Invoke-RollingPoolUpdate";            Defaults = @{ RepoUrl = "https://repo.ops.xenserver.com/xs9"; SourceUrl = "https://repo-src.ops.xenserver.com/xs9" } }
    "pvs-accelerator"                = @{ Function = "Invoke-PvsAccelerator";               Defaults = @{} }
    "configure-pvs-accelerator"      = @{ Function = "Invoke-ConfigurePvsAccelerator";      Defaults = @{ VmName = "db-01" } }
    "manage-ssh-access"              = @{ Function = "Invoke-ManageSshAccess";              Defaults = @{} }
    "manage-vtpm"                    = @{ Function = "Invoke-ManageVtpm";                   Defaults = @{} }
    "configure-dynamic-memory"       = @{ Function = "Invoke-ConfigureDynamicMemory";       Defaults = @{} }
    "manage-vm-media"                = @{ Function = "Invoke-ManageVmMedia";                Defaults = @{} }
    "backup-host-config"             = @{ Function = "Invoke-BackupHostConfig";             Defaults = @{} }
    "manage-sr-lifecycle"            = @{ Function = "Invoke-ManageSrLifecycle";            Defaults = @{} }
    "reconnect-sr-storage"           = @{ Function = "Invoke-ReconnectSrStorage";           Defaults = @{} }
    "export-import-vdi"              = @{ Function = "Invoke-ExportImportVdi";              Defaults = @{} }
    "set-default-sr"                 = @{ Function = "Invoke-SetDefaultSr";                 Defaults = @{} }
    "server-status-report"           = @{ Function = "Invoke-ServerStatusReport";           Defaults = @{} }
    "configure-disaster-recovery"    = @{ Function = "Invoke-ConfigureDisasterRecovery";    Defaults = @{} }
    "disaster-recovery-failover"     = @{ Function = "Invoke-DisasterRecoveryFailover";     Defaults = @{ Target = "192.0.2.31"; TargetIqn = "iqn.2009-01.com.example:replica-0"; ScsiId = "360a980004265656d5f4a2d63764e5738" } }
    "manage-secureboot-certificates" = @{ Function = "Invoke-ManageSecurebootCertificates"; Defaults = @{} }
    "restart-host"                   = @{ Function = "Invoke-RestartHost";                  Defaults = @{} }
    "manage-crash-dumps"             = @{ Function = "Invoke-ManageCrashDumps";             Defaults = @{} }
    "configure-pool-options"         = @{ Function = "Invoke-ConfigurePoolOptions";         Defaults = @{} }
    "configure-console-access"       = @{ Function = "Invoke-ConfigureConsoleAccess";       Defaults = @{} }
    "configure-host-storage"         = @{ Function = "Invoke-ConfigureHostStorage";         Defaults = @{} }
    "configure-syslog"               = @{ Function = "Invoke-ConfigureSyslog";              Defaults = @{} }
    "manage-driver-variants"         = @{ Function = "Invoke-ManageDriverVariants";         Defaults = @{} }
    "vm-from-snapshot"               = @{ Function = "Invoke-VmFromSnapshot";               Defaults = @{ VmName = "db-01" } }
    "attach-existing-disk"           = @{ Function = "Invoke-AttachExistingDisk";           Defaults = @{} }
    "export-import-vm"               = @{ Function = "Invoke-ExportImportVm";               Defaults = @{ VmName = "db-01" } }
    "changed-block-tracking"         = @{ Function = "Invoke-ChangedBlockTracking";         Defaults = @{} }
    "control-domain-memory"          = @{ Function = "Invoke-ControlDomainMemory";          Defaults = @{} }
    "rrd-metrics"                    = @{ Function = "Invoke-RrdMetrics";                   Defaults = @{} }
    "reclaim-space"                  = @{ Function = "Invoke-ReclaimSpace";                 Defaults = @{} }
    "vm-ip-address"                  = @{ Function = "Invoke-VmIpAddress";                  Defaults = @{} }
    "manage-ad-users"                = @{ Function = "Invoke-ManageAdUsers";                Defaults = @{ Domain = ""; AdminUser = "alice"; AdminPassword = "Password1"; NewUser = "alice"; Ldaps = "false" } }
    "create-iscsi-sr"                = @{ Function = "Invoke-CreateIscsiSr";                Defaults = @{ Target = "192.0.2.30"; ScsiId = "360a980004265656d5f4a2d63764e5734" } }
    "create-smb-sr"                  = @{ Function = "Invoke-CreateSmbSr";                  Defaults = @{ Server = "192.0.2.40"; Share = "/vmstore"; SmbUsername = "Administrator"; SmbPassword = "Password1" } }
    "create-hba-sr"                  = @{ Function = "Invoke-CreateHbaSr";                  Defaults = @{} }
    "create-iso-sr"                  = @{ Function = "Invoke-CreateIsoSr";                  Defaults = @{ Location = "192.0.2.10:/isos" } }
    "configure-nrpe"                 = @{ Function = "Invoke-ConfigureNrpe";                Defaults = @{} }
    "configure-snmp"                 = @{ Function = "Invoke-ConfigureSnmp";                Defaults = @{ TrapDestination = "192.0.2.50" } }
    "configure-clustering"           = @{ Function = "Invoke-ConfigureClustering";          Defaults = @{} }
    "manage-pool-membership"         = @{ Function = "Invoke-ManagePoolMembership";         Defaults = @{} }
    "create-bond"                    = @{ Function = "Invoke-CreateBond";                   Defaults = @{} }
    "manage-vapp"                    = @{ Function = "Invoke-ManageVapp";                   Defaults = @{ VmName = "db-01" } }
    "attach-usb-device"              = @{ Function = "Invoke-AttachUsbDevice";              Defaults = @{ VmName = "web-01" } }
    "wlb-recommendations"            = @{ Function = "Invoke-WlbRecommendations";           Defaults = @{ VmName = "web-01"; WlbHostPort = "wlb.example:8012"; WlbUsername = "wlbuser"; WlbPassword = "wlbpass"; WlbCertificate = "" } }
}

if (-not $WORKFLOWS.ContainsKey($Workflow)) {
    Write-Error "usage: workflows.ps1 <$($WORKFLOWS.Keys -join '|')|cross-pool-copy-vm> <url> <user> <password> [key=value ...]"
    exit 2
}

$entry = $WORKFLOWS[$Workflow]
$callParams = @{ Url = $Url; UserName = $UserName; Password = $Password }
foreach ($k in $entry.Defaults.Keys) { $callParams[$k] = $entry.Defaults[$k] }
foreach ($arg in $WorkflowArgs) {
    if ($arg -notmatch '=') {
        Write-Error "extra arguments must be key=value (got '$arg')"
        exit 2
    }
    $parts = $arg -split '=', 2
    # The same key=value spelling as the other languages' samples (snake_case, e.g. source_vm=win) maps
    # onto this script's PascalCase parameters (-SourceVm); a PascalCase key works too.
    $key = (($parts[0] -split '_') | ForEach-Object { $_.Substring(0, 1).ToUpper() + $_.Substring(1) }) -join ''
    # true/false become booleans, for the [bool] parameters.
    $callParams[$key] = if ($parts[1] -in 'true', 'false') { [bool]::Parse($parts[1]) } else { $parts[1] }
}

& $entry.Function @callParams
