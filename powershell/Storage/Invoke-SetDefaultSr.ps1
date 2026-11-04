function Invoke-SetDefaultSr {
    <#
    .SYNOPSIS
        Set the pool's default storage.
    .DESCRIPTION
        Choose where the pool puts new disks, suspended VMs' memory images and host crash dumps by default,
        then put the original choice back.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password,
        [string]$NfsServer = "192.0.2.10",
        [string]$NfsPath = "/export/spare"
    )
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password
    $pool = Get-XenPool | Select-Object -First 1

    # Capture all three separately. New disks land on the default SR, a suspended VM's memory image goes
    # to the suspend-image SR and host crash dumps to the crash-dump SR. They are usually the same
    # storage but need not be, and a pool that has never suspended or crashed anything can legitimately
    # leave the latter two unset - so restoring all three from the default would quietly invent settings
    # that were not there. The record already holds each as a reference, so it can be handed straight
    # back to Set-XenPool later.
    $before = $pool.default_SR
    $beforeSuspend = $pool.suspend_image_SR
    $beforeCrash = $pool.crash_dump_SR
    Write-Host ("default storage:  {0}" -f (Get-SrLabel $before))
    Write-Host ("  suspend images: {0}" -f (Get-SrLabel $beforeSuspend))
    Write-Host ("  crash dumps:    {0}" -f (Get-SrLabel $beforeCrash))

    # Somewhere to switch to. A pool default has to be reachable from every host, so it is a shared SR;
    # a local one would strand any VM whose disk landed on the wrong host.
    $sr = New-XenSR -XenHost (Get-XenHost | Select-Object -First 1) -PhysicalSize 0 `
        -DeviceConfig @{ server = $NfsServer; serverpath = $NfsPath; nfsversion = "3" } `
        -NameLabel "sdk-example-default" -NameDescription "SR used by the SDK default-storage example" `
        -Type "nfs" -ContentType "user" -Shared $true -PassThru

    $srRef = $sr | ConvertTo-XenRef
    $pool | Set-XenPool -DefaultSR $srRef -SuspendImageSR $srRef -CrashDumpSR $srRef
    Write-Host ("  switched to:    {0}" -f (Get-SrLabel (Get-XenPool -Ref $pool.opaque_ref).default_SR))

    # Restore the original choice before tidying up: an SR that is still the pool default is the awkward
    # one to remove.
    $pool | Set-XenPool -DefaultSR $before -SuspendImageSR $beforeSuspend -CrashDumpSR $beforeCrash
    @($sr.PBDs | ForEach-Object { Get-XenPBD -Ref $_.opaque_ref }) | Invoke-XenPBD -XenAction Unplug
    $sr | Invoke-XenSR -XenAction Forget
    Write-Host ("  restored to:    {0}" -f (Get-SrLabel (Get-XenPool -Ref $pool.opaque_ref).default_SR))
    Write-Host "OK: set-default-sr"
    $session | Disconnect-XenServer
}

function Get-SrLabel {
    <#
    .SYNOPSIS
        An SR's name, tolerating the null reference an unset pool field holds.
    #>
    param($SrRef)
    if (-not $SrRef -or $SrRef.opaque_ref -eq "OpaqueRef:NULL") { return "(none)" }
    (Get-XenSR -Ref $SrRef.opaque_ref).name_label
}
