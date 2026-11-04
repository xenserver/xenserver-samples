function Invoke-CreateIscsiSr {
    <#
    .SYNOPSIS
        Create an iSCSI SR.
    .DESCRIPTION
        Connect a storage repository to a LUN on an iSCSI target, discovering the target's IQNs and then the
        LUNs behind one, as the New SR wizard does. Creating the SR formats the LUN, and a shared array
        offers many targets, so name yours with target_iqn.
    .EXAMPLE
        Invoke-CreateIscsiSr -Url https://xenserver -UserName root -Password $password
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password,
        [Parameter(Mandatory = $true)][string]$Target,
        [string]$Port,
        [string]$ChapUser,
        [string]$ChapPassword,
        [string]$TargetIqn,
        [string]$SrName = "sdk-example-iscsi"
    )
    # Connect an SR to a LUN on the iSCSI target, discovering the IQN and the LUN the way the New SR
    # wizard does: a device-config that's missing a piece makes the backend fail on purpose, and the
    # failure carries an XML fragment listing what it needs next.
    #
    # SR.create formats the chosen LUN - this is destructive, so pick carefully on a real target: pass
    # TargetIqn to name yours (see Select-TargetIqn).
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password
    $xenHost = Get-XenHost | Select-Object -First 1
    $dc = @{ target = $Target }
    if ($Port) { $dc["port"] = $Port }
    if ($ChapUser) { $dc["chapuser"] = $ChapUser; $dc["chappassword"] = $ChapPassword }

    # First failing probe: target only -> the backend lists the IQNs it offers.
    $iqnXml = [xml](Invoke-ProbeForFailure -XenHostRef $xenHost.opaque_ref -DeviceConfig $dc -SmType lvmoiscsi)
    $dc["targetIQN"] = Select-TargetIqn -IqnXml $iqnXml -Target $Target -TargetIqn $TargetIqn
    Write-Host "Discovered IQN: $($dc['targetIQN'])"

    # Second failing probe: +targetIQN -> the backend lists the LUNs behind it. Real create also
    # carries LUNid whenever it is known.
    $lunXml = [xml](Invoke-ProbeForFailure -XenHostRef $xenHost.opaque_ref -DeviceConfig $dc -SmType lvmoiscsi)
    $luns = @($lunXml.SelectNodes("//LUN"))
    $lun = $luns[0]
    $dc["SCSIid"] = $lun.SCSIid
    $lunIdNode = $lun.SelectSingleNode("LUNid")
    $dc["LUNid"] = if ($lunIdNode) { $lunIdNode.InnerText } else { [string]([array]::IndexOf($luns, $lun)) }
    Write-Host "Discovered LUN $($dc['LUNid']) (SCSIid $($dc['SCSIid']))"

    $sr = New-XenSR -XenHost $xenHost -DeviceConfig $dc -PhysicalSize 0 `
        -NameLabel $SrName -NameDescription "iSCSI SR created by the SDK example" `
        -Type "lvmoiscsi" -ContentType "user" -Shared $true -PassThru
    Write-Host "Created SR: $($sr.uuid) ($([math]::Floor([long]($sr.physical_size) / 1GB)) GiB)"
    Invoke-DetachAndForgetSr -Ref $sr.opaque_ref
    Write-Host "OK: create-iscsi-sr"
    $session | Disconnect-XenServer
}

function Select-TargetIqn {
    <#
    .SYNOPSIS
        Pick the IQN from an iSCSI discovery probe.
    .DESCRIPTION
        The caller's, if named (it must be one the target offers), else the first. An array usually offers
        many targets - one per LUN, often belonging to different users - so on shared storage always name
        yours: SR.create formats the LUN behind it.
    #>
    param(
        [Parameter(Mandatory = $true)][xml]$IqnXml,
        [Parameter(Mandatory = $true)][string]$Target,
        [string]$TargetIqn
    )
    $offered = @($IqnXml.SelectNodes("//TargetIQN") | ForEach-Object { $_.InnerText })
    if (-not $TargetIqn) { return $offered[0] }
    if ($offered -notcontains $TargetIqn) { throw "target $Target does not offer IQN $TargetIqn" }
    return $TargetIqn
}
