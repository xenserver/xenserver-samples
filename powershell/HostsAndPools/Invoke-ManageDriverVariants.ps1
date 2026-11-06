function Invoke-ManageDriverVariants {
    <#
    .SYNOPSIS
        Manage device driver variants.
    .DESCRIPTION
        Inspect a host's device drivers and choose which variant of one to use, seeing the difference
        between the variant that is selected and the one currently loaded.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password
    )
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password
    $xenHost = Get-XenHost -Ref (Get-XenPool | Select-Object -First 1).master

    # A driver can ship in several variants - a vendor build alongside the one in the distribution, say.
    # One is SELECTED (what the host will load) and one is ACTIVE (what it has loaded); they differ
    # until the host reboots, which is what makes selecting a variant a scheduled change rather than an
    # immediate one.
    $drivers = @(Get-XenHostDriver | Where-Object { $_.host -eq $xenHost })
    Write-Host "$($xenHost.name_label) has $($drivers.Count) driver(s)"
    $drivers | Sort-Object name | Select-Object -First 3 | ForEach-Object {
        Write-Host ("  {0,-14} {1,-10} {2} variant(s), active={3}" -f
            $_.name, $_.type, $_.variants.Count, (Get-DriverVariantName $_.active_variant))
    }

    # Select a variant explicitly. It becomes the selected one immediately; whether it is also active
    # depends on whether the hardware is present and the driver already loaded. Host_driver.select
    # refuses a variant whose hardware isn't present (HOST_DRIVER_NO_HARDWARE) - and a host lists
    # drivers for plenty of devices it doesn't have - so pick a driver for hardware this host actually
    # has, and one of its variants that is usable.
    $usable = @($drivers | Sort-Object name | ForEach-Object {
        $driver = $_
        $driver.variants | Where-Object { (Get-XenDriverVariant -Ref $_).hardware_present } |
            ForEach-Object { [pscustomobject]@{ Driver = $driver; Variant = $_ } }
    })
    if (-not $usable) { throw "no driver on $($xenHost.name_label) has a variant for hardware it has" }
    $target = $usable[0].Driver
    $variant = $usable[0].Variant
    Invoke-XenHostDriver -Ref $target -XenAction Select -Variant $variant
    $after = Get-XenHostDriver -Ref $target
    Write-Host "  $($after.name): selected $(Get-DriverVariantName $after.selected_variant), active $(Get-DriverVariantName $after.active_variant)"

    Write-Host "OK: manage-driver-variants"
    $session | Disconnect-XenServer
}

function Get-DriverVariantName {
    <#
    .SYNOPSIS
        A driver variant's name, tolerating the null reference an unloaded driver has.
    #>
    param($VariantRef)
    if (-not $VariantRef -or $VariantRef -eq "OpaqueRef:NULL") { return "(none)" }
    (Get-XenDriverVariant -Ref $VariantRef).name
}
