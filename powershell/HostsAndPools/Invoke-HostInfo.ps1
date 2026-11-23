function Invoke-HostInfo {
    <#
    .SYNOPSIS
        Host information.
    .DESCRIPTION
        Read a host's software version, edition and CPU topology (sockets and cores).
    .EXAMPLE
        Invoke-HostInfo -Url https://xenserver -UserName root -Password $password
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password
    )
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password
    $xenHost = Get-XenHost | Select-Object -First 1
    $sw = $xenHost.software_version
    $cpu = $xenHost.cpu_info
    $pv = if ($sw.ContainsKey("product_version")) { $sw["product_version"] } else { "?" }
    $cc = if ($cpu.ContainsKey("cpu_count")) { $cpu["cpu_count"] } else { "?" }
    $sc = if ($cpu.ContainsKey("socket_count")) { $cpu["socket_count"] } else { "?" }
    Write-Host "Host:     $($xenHost.name_label)"
    Write-Host "Version:  $pv"
    Write-Host "Edition:  $($xenHost.edition)"
    Write-Host "CPUs:     $cc across $sc socket(s)"
    # The physical identity, straight off the host's DMI/SMBIOS tables. The serial number is what you
    # quote to the hardware vendor, so it identifies this machine and not just its model.
    $bios = $xenHost.bios_strings
    Write-Host "Hardware: $($bios['system-manufacturer']) $($bios['system-product-name'])"
    Write-Host "Serial:   $($bios['system-serial-number'])"
    Write-Host "BIOS:     $($bios['bios-version'])"
    Write-Host "OK: host-info"
    $session | Disconnect-XenServer
}
