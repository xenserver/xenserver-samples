function Invoke-CreateHbaSr {
    <#
    .SYNOPSIS
        Create an HBA SR.
    .DESCRIPTION
        Connect a shared storage repository to a fibre-channel (HBA) LUN: discover the LUNs the host can see
        with a deliberately failing probe, then create the SR by SCSI ID. Creating the SR formats the LUN.
    .EXAMPLE
        Invoke-CreateHbaSr -Url https://xenserver -UserName root -Password $password
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password,
        [string]$ScsiId = "",
        [string]$SrName = "sdk-example-hba"
    )
    # Connect a shared SR to a fibre-channel (HBA) LUN, discovering it first: probing with no SCSIid fails on
    # purpose and lists every LUN the backend can see.
    #
    # SR.create formats the chosen LUN - this is destructive. On shared FC storage a host sees LUNs other
    # hosts are using, so name the one that is yours (-ScsiId); with none, the first LUN listed is taken,
    # which is only right on a dedicated test target.
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password
    $xenHost = Get-XenHost | Select-Object -First 1

    # The root element varies by backend; find BlockDevice entries by tag wherever they are.
    $devlistXml = [xml](Invoke-ProbeForFailure -XenHostRef $xenHost.opaque_ref -DeviceConfig @{} -SmType lvmohba)
    $device = $devlistXml.SelectNodes("//BlockDevice") |
        Where-Object { -not $ScsiId -or $_.SCSIid -eq $ScsiId } | Select-Object -First 1
    if (-not $device) { throw "no LUN with SCSIid $ScsiId is visible to this host" }
    $scsiId = $device.SCSIid
    $path = $device.path
    Write-Host "Discovered LUN: SCSIid $scsiId on $path"

    # SCSIid is all lvmohba needs. (The probe's <path> is for display: on a real host it reads
    # like "/dev/sde [sdc] [sdg] [sdi]", one entry per path.)
    $deviceConfig = @{ SCSIid = $scsiId }

    # SCSIid alone is also enough to probe the LUN itself: an <SR> in the answer means one is already
    # there, and SR.create would format it. Reattach that SR rather than destroying it.
    $probe = Invoke-XenSR -Ref "OpaqueRef:NULL" -XenAction Probe -XenHost $xenHost.opaque_ref `
        -DeviceConfig $deviceConfig -Type lvmohba -SmConfig @{} -PassThru
    $existing = @(([xml]$probe).SelectNodes('/SRlist/SR'))
    if ($existing.Count -gt 0) {
        throw "LUN $scsiId already holds SR $("$($existing[0].UUID)".Trim()); creating an SR here would " +
            "format it - reattach the existing SR instead of creating a new one"
    }

    $sr = New-XenSR -XenHost $xenHost -DeviceConfig $deviceConfig -PhysicalSize 0 `
        -NameLabel $SrName -NameDescription "HBA SR created by the SDK example" `
        -Type "lvmohba" -ContentType "user" -Shared $true -PassThru
    Write-Host "Created SR: $($sr.uuid) ($([math]::Floor([long]($sr.physical_size) / 1GB)) GiB)"
    # Tidy up: this example created the SR, so destroy it - a forgotten SR would stay on the LUN.
    # SR.destroy needs it detached from every host first.
    Get-XenPBD | Where-Object { $_.SR.opaque_ref -eq $sr.opaque_ref -and $_.currently_attached } |
        ForEach-Object { $_ | Invoke-XenPBD -XenAction Unplug }
    Remove-XenSR -Ref $sr.opaque_ref
    Write-Host "OK: create-hba-sr"
    $session | Disconnect-XenServer
}
