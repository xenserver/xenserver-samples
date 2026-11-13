function Invoke-ConfigureHostStorage {
    <#
    .SYNOPSIS
        Configure host storage.
    .DESCRIPTION
        Set a host's iSCSI initiator name and turn on storage multipathing, then restore both.
    .EXAMPLE
        Invoke-ConfigureHostStorage -Url https://xenserver -UserName root -Password $password
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password
    )
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password
    $xenHost = Get-XenHost -Ref (Get-XenPool | Select-Object -First 1).master

    # The IQN identifies this host to iSCSI targets, so a target's access list is written against it -
    # changing it on a host with live iSCSI storage cuts it off. Existing iSCSI SRs must be detached
    # first: changing the IQN underneath them can make the host unable to reconnect to new or existing
    # SRs until the storage target is updated to match. Multipathing uses every path to the storage
    # rather than one, and on real hardware you put the host into maintenance mode before changing it,
    # because the paths are rebuilt.
    $beforeIqn = $xenHost.iscsi_iqn
    $beforeMultipathing = $xenHost.multipathing
    Write-Host "$($xenHost.name_label): iSCSI IQN '$beforeIqn', multipathing $beforeMultipathing"

    $xenHost | Set-XenHost -IscsiIqn "iqn.2026-01.com.example:$($xenHost.name_label)"
    $xenHost | Set-XenHost -Multipathing $true
    $updated = Get-XenHost -Ref $xenHost
    Write-Host "  IQN now:      $($updated.iscsi_iqn)"
    Write-Host "  multipathing: $($updated.multipathing)"

    # set_iscsi_iqn refuses an empty string (INVALID_VALUE); only restore it if this host actually had
    # one set before - a host that has never had an IQN configured has it empty, and there is no way to
    # set it back to empty through this call.
    if ($beforeIqn) { $xenHost | Set-XenHost -IscsiIqn $beforeIqn }
    $xenHost | Set-XenHost -Multipathing $beforeMultipathing
    Write-Host "  restored"
    Write-Host "OK: configure-host-storage"
    $session | Disconnect-XenServer
}
