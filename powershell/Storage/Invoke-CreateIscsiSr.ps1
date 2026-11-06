function Invoke-CreateIscsiSr {
    <#
    .SYNOPSIS
        Create an iSCSI SR.
    .DESCRIPTION
        Connect a storage repository to a LUN on an iSCSI target, discovering the target's IQNs and then the
        LUNs behind one. Creating the SR formats the LUN, and a shared array offers many targets, so name
        yours with target_iqn; if the target behind it offers more than one LUN, name yours with ScsiId too.
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
        [string]$ScsiId,
        [string]$SrName = "sdk-example-iscsi"
    )
    # Connect an SR to a LUN on the iSCSI target, discovering the IQN and the LUN first: a device-config
    # that's missing a piece makes the backend fail on purpose, and the failure carries an XML fragment
    # listing what it needs next.
    #
    # SR.create formats the chosen LUN - this is destructive, so pick carefully on a real target: pass
    # TargetIqn to name yours (see Select-TargetIqn), and ScsiId too if more than one LUN is offered
    # behind it (see Select-Lun). Before creating, this probes the chosen LUN itself to make sure it is
    # not already in use by another SR - formatting over one would destroy it.
    #
    # The CHAP password (if any) travels as a Secret, not plaintext device-config, as Invoke-CreateSmbSr
    # already does for its share password.
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password
    $xenHost = Get-XenHost | Select-Object -First 1
    $dc = @{ target = $Target }
    if ($Port) { $dc["port"] = $Port }
    $secret = $null
    if ($ChapUser) {
        $dc["chapuser"] = $ChapUser
        $secret = New-XenSecret -Value $ChapPassword -OtherConfig @{} -PassThru
        $dc["chappassword_secret"] = $secret.uuid
    }

    try {
        # First failing probe: target only -> the backend lists the IQNs it offers.
        $iqnXml = [xml](Invoke-ProbeForFailure -XenHostRef $xenHost.opaque_ref -DeviceConfig $dc -SmType lvmoiscsi)
        $dc["targetIQN"] = Select-TargetIqn -IqnXml $iqnXml -Target $Target -TargetIqn $TargetIqn
        Write-Host "Discovered IQN: $($dc['targetIQN'])"

        # Second failing probe: +targetIQN -> the backend lists the LUNs behind it. Real create also
        # carries LUNid whenever it is known.
        $lunXml = [xml](Invoke-ProbeForFailure -XenHostRef $xenHost.opaque_ref -DeviceConfig $dc -SmType lvmoiscsi)
        $luns = @($lunXml.SelectNodes("//LUN"))
        $lun = Select-Lun -Luns $luns -ScsiId $ScsiId
        $dc["SCSIid"] = $lun.SCSIid
        $lunIdNode = $lun.SelectSingleNode("LUNid")
        $dc["LUNid"] = if ($lunIdNode) { $lunIdNode.InnerText } else { [string]([array]::IndexOf($luns, $lun)) }
        Write-Host "Discovered LUN $($dc['LUNid']) (SCSIid $($dc['SCSIid']))"

        # The device-config is now complete enough to create from - which means it is also complete
        # enough to probe the LUN itself: an <SR> in the answer means one is already there, and
        # SR.create would format it. Reattach that SR rather than destroying it.
        $probe = Invoke-XenSR -Ref "OpaqueRef:NULL" -XenAction Probe -XenHost $xenHost.opaque_ref -DeviceConfig $dc `
            -Type lvmoiscsi -SmConfig @{} -PassThru
        $existing = @(([xml]$probe).SelectNodes('/SRlist/SR'))
        if ($existing.Count -gt 0) {
            throw "LUN $($dc['SCSIid']) already holds SR $("$($existing[0].UUID)".Trim()); creating an SR " +
                "here would format it - reattach the existing SR instead of creating a new one"
        }

        $sr = New-XenSR -XenHost $xenHost -DeviceConfig $dc -PhysicalSize 0 `
            -NameLabel $SrName -NameDescription "iSCSI SR created by the SDK example" `
            -Type "lvmoiscsi" -ContentType "user" -Shared $true -PassThru
        Write-Host "Created SR: $($sr.uuid) ($([math]::Floor([long]($sr.physical_size) / 1GB)) GiB)"
        # Tidy up: this example created the SR, so destroy it - a forgotten SR would stay on the LUN.
        # SR.destroy needs it detached from every host first.
        Get-XenPBD | Where-Object { $_.SR.opaque_ref -eq $sr.opaque_ref -and $_.currently_attached } |
            ForEach-Object { $_ | Invoke-XenPBD -XenAction Unplug }
        Remove-XenSR -Ref $sr.opaque_ref
    }
    finally {
        if ($secret) { Remove-XenSecret -Ref $secret.opaque_ref }
    }
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

function Select-Lun {
    <#
    .SYNOPSIS
        Pick the LUN behind the chosen IQN.
    .DESCRIPTION
        The caller's SCSIid, if named (it must be one on offer), else the one LUN, if that target offers
        only one. Choose a LUN automatically only when exactly one is on offer, and otherwise make the
        caller choose - picking blindly on a shared target risks formatting someone else's disk.
    #>
    param(
        [Parameter(Mandatory = $true)][array]$Luns,
        [string]$ScsiId
    )
    if ($ScsiId) {
        $lun = $Luns | Where-Object { $_.SCSIid -eq $ScsiId } | Select-Object -First 1
        if (-not $lun) {
            $offered = ($Luns | ForEach-Object { $_.SCSIid }) -join ", "
            throw "target does not offer a LUN with SCSIid $ScsiId; offered: $offered"
        }
        return $lun
    }
    if ($Luns.Count -eq 1) { return $Luns[0] }
    $offered = ($Luns | ForEach-Object { "$($_.SCSIid) ($($_.size) bytes)" }) -join ", "
    throw "target offers $($Luns.Count) LUNs; name one with ScsiId: $offered"
}
