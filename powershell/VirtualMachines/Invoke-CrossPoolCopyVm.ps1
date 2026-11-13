function Invoke-CrossPoolCopyVm {
    <#
    .SYNOPSIS
        Cross-pool copy a VM.
    .DESCRIPTION
        Copy a VM from one pool to another: open a session to each pool, obtain a receiver token on the
        destination, then send a copy of the VM from the source. Takes the destination pool's URL as an
        extra argument after the password.
    .EXAMPLE
        Invoke-CrossPoolCopyVm -Url https://poolA -UserName root -Password $password -DestUrl https://poolB `
    .EXAMPLE
        [-DestUserName root -DestPassword $destPassword] [-VmName db-01]
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password,
        [Parameter(Mandatory = $true)][string]$DestUrl,
        [string]$VmName = "db-01",
        # The destination pool's credentials, if they differ from the source's.
        [string]$DestUserName = $UserName,
        [string]$DestPassword = $Password,
        # A network on the destination pool to carry the migration traffic - pass the name of a
        # dedicated migration network. Defaults to the destination's management network.
        [string]$TransferNetwork
    )
    # Two pools, so two sessions. Every cmdlet takes -SessionOpaqueRef, so we drive each pool explicitly
    # (Connect-Example sets a default session too, but being explicit keeps the two pools apart).
    $source = Connect-Example -Url $Url -UserName $UserName -Password $Password
    $dest = Connect-Example -Url $DestUrl -UserName $DestUserName -Password $DestPassword
    $srcRef = $source.opaque_ref
    $dstRef = $dest.opaque_ref

    # Destination: choose a host, network and SR, then ask for a receiver token (a string->string map).
    # The disks go to the destination pool's default SR.
    $destPool = Get-XenPool -SessionOpaqueRef $dstRef | Select-Object -First 1
    $destHost = Get-XenHost -SessionOpaqueRef $dstRef -Ref $destPool.master
    $destSr = Get-XenSR -SessionOpaqueRef $dstRef -Ref $destPool.default_SR
    $managementPif = Get-XenPIF -SessionOpaqueRef $dstRef |
        Where-Object { $_.management -and $_.host -eq $destHost } | Select-Object -First 1
    $destManagementNet = Get-XenNetwork -SessionOpaqueRef $dstRef -Ref $managementPif.network
    if ($TransferNetwork) {
        $migrationNet = Get-XenNetwork -SessionOpaqueRef $dstRef -Name $TransferNetwork | Select-Object -First 1
        if (-not $migrationNet) { throw "No network named '$TransferNetwork' was found on the destination pool." }
    }
    else {
        # For performance, production use should carry migration traffic over a dedicated network
        # rather than the management network - pass -TransferNetwork with the name of one.
        $migrationNet = $destManagementNet
    }
    $receiver = $destHost | Invoke-XenHost -SessionOpaqueRef $dstRef -XenAction MigrateReceive `
        -Network $migrationNet -Options @{} -PassThru

    # Source: find the VM, then map every disk to the destination SR and every NIC to the destination
    # pool's management network (the VM's guest-visible NICs, independent of the migration transfer).
    # migrate_send's maps are strongly-typed (source XenRef -> destination XenRef) dictionaries, so build
    # them as such; ConvertTo-XenRef turns each destination object into the typed ref the values need
    # (the source refs come straight off the VM's .VBDs/.VIFs).
    $vm = Get-XenVM -SessionOpaqueRef $srcRef -Name $VmName |
        Where-Object { -not $_.is_a_template -and -not $_.is_control_domain } | Select-Object -First 1

    $vdiMap = New-Object 'System.Collections.Generic.Dictionary[XenAPI.XenRef[XenAPI.VDI], XenAPI.XenRef[XenAPI.SR]]'
    foreach ($vbdRef in $vm.VBDs) {
        $vbd = Get-XenVBD -SessionOpaqueRef $srcRef -Ref $vbdRef
        if ($vbd.type -eq 'Disk' -and $vbd.VDI -ne 'OpaqueRef:NULL') {
            $vdiMap[$vbd.VDI] = ConvertTo-XenRef -XenObject $destSr
        }
    }
    $vifMap = New-Object 'System.Collections.Generic.Dictionary[XenAPI.XenRef[XenAPI.VIF], XenAPI.XenRef[XenAPI.Network]]'
    foreach ($vifRef in $vm.VIFs) { $vifMap[$vifRef] = ConvertTo-XenRef -XenObject $destManagementNet }

    # Send with copy=true (the source VM is left intact). Dest/VdiMap/VifMap/VgpuMap are the migrate_send
    # action's parameters.
    # The VMs the destination already has, to tell the copy apart afterwards (never by name alone).
    $before = @(Get-XenVM -SessionOpaqueRef $dstRef | ForEach-Object { $_.uuid })
    $vm | Invoke-XenVM -SessionOpaqueRef $srcRef -XenAction MigrateSend -Dest $receiver -Live $false `
        -VdiMap $vdiMap -VifMap $vifMap -Options @{ copy = "true" } -VgpuMap @{}

    $stillThere = [bool](Get-XenVM -SessionOpaqueRef $srcRef -Name $VmName |
        Where-Object { -not $_.is_a_template -and -not $_.is_control_domain })
    Write-Host "Sent '$VmName' to the destination pool (copy); source still present: $stillThere"

    # Tidy up so the example is repeatable: the copy and its disks, on the destination pool.
    $copy = Get-XenVM -SessionOpaqueRef $dstRef | Where-Object { $_.uuid -notin $before } |
        Select-Object -First 1
    if ($copy) {
        Write-Host "  the copy on the destination: $($copy.name_label) ($($copy.uuid))"
        $copyVdis = @($copy.VBDs | ForEach-Object { Get-XenVBD -SessionOpaqueRef $dstRef -Ref $_ } |
            Where-Object { $_.type -eq 'Disk' -and $_.VDI -ne 'OpaqueRef:NULL' } |
            ForEach-Object { $_.VDI })
        Remove-XenVM -SessionOpaqueRef $dstRef -Ref $copy
        $copyVdis | ForEach-Object { Remove-XenVDI -SessionOpaqueRef $dstRef -Ref $_ }
    }
    else {
        # No new VM on the destination: the copy did not arrive, so there is nothing to tidy up.
        Write-Host "  the copy on the destination: not found (nothing to tidy up)"
    }
    Write-Host "OK: cross-pool-copy-vm"
    $source | Disconnect-XenServer
    $dest | Disconnect-XenServer
}
