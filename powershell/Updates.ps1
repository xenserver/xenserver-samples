#
# Copyright (c) Cloud Software Group, Inc.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
#
#   1) Redistributions of source code must retain the above copyright
#      notice, this list of conditions and the following disclaimer.
#
#   2) Redistributions in binary form must reproduce the above
#      copyright notice, this list of conditions and the following
#      disclaimer in the documentation and/or other materials
#      provided with the distribution.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
# "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
# LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS
# FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE
# COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT,
# INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
# (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
# SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
# HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT,
# STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
# ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED
# OF THE POSSIBILITY OF SUCH DAMAGE.
#

Param (
    [string]$Server,
    [string]$Username,
    [string]$Passwd,
    [ValidateSet("EarlyAccess", "Normal")][string]$Channel
)

# Update channel URL prefixes
$binRepoPrefix = "https://repo.ops.xenserver.com/xs8"
$srcRepoPrefix = "https://repo-src.ops.xenserver.com/xs8"

enum RepoType { Base; EarlyAccess; Normal }

function Get-RepoKey([RepoType]$RepoType) {
    switch ($RepoType) {
        Base { "base_repo" }
        EarlyAccess { "early_access_repo" }
        Normal { "normal_repo" }
    }
}

function Get-RepoDescription([RepoType]$RepoType) {
    switch ($RepoType) {
        Base { "Base" }
        EarlyAccess { "Early Access" }
        Normal { "Normal" }
    }
}

function Get-BinUrl([RepoType]$RepoType) {
    "$binRepoPrefix/$RepoType".ToLower()
}

function Get-SourceUrl([RepoType]$RepoType) {
    "$srcRepoPrefix/$RepoType".ToLower()
}

<#
.SYNOPSIS
    Configure the pool to use the specified update channel (Early Access or Normal)
#>
function Set-UpdateChannel {
    param(
        [XenAPI.Pool]$Pool,

        [ValidateSet("EarlyAccess", "Normal")]
        [RepoType]$RepoType
    )

    $key = Get-RepoKey $RepoType
    $descr = Get-RepoDescription $RepoType
    $binUrl = Get-BinUrl $RepoType
    $srcUrl = Get-SourceUrl $RepoType

    $oldEnabledRepos = $Pool.repositories | Get-XenRepository
    $updateRepo = $oldEnabledRepos | Where-Object { ($_.name_label -eq $key) -or ($_.binary_url -eq $binUrl) }

    if ($null -ne $updateRepo) {
        Write-Host "Update channel" $updateRepo.name_description "is already enabled"
        return
    }

    foreach ($rep in $oldEnabledRepos) {
        Write-Host "Disabling previous update channel" $rep.name_description
        Remove-XenPoolProperty -Pool $Pool -Repository $rep
    }

    $updateRepo = Get-XenRepository |`
        Where-Object { ($_.name_label -eq $key) -or ($_.binary_url -eq $binUrl) } |`
        Select-Object -First 1

    if ($null -eq $updateRepo) {
        $baseKey = Get-RepoKey Base
        $baseDescr = Get-RepoDescription Base
        $baseBinUrl = Get-BinUrl Base
        $baseSrcUrl = Get-SourceUrl Base

        $baseRepo = Get-XenRepository |`
            Where-Object { ($_.name_label -eq $baseKey) -or ($_.binary_url -eq $binUrl) } |`
            Select-Object -First 1

        if ($null -eq $baseRepo) {
            Write-Host "Introducing update channel" $baseDescr
            Invoke-XenRepository -XenAction Introduce -Name "dummy" -BinaryUrl $baseBinUrl -SourceUrl $baseSrcUrl `
                -NameLabel $baseKey -NameDescription $baseDescr -Update $false -GpgkeyPath ""
        }

        Write-Host "Introducing update channel" $descr
        $updateRepo = Invoke-XenRepository -XenAction Introduce -Name "dummy" -BinaryUrl $binUrl -SourceUrl $srcUrl `
            -NameLabel $key -NameDescription $descr -Update $true -GpgkeyPath "" -PassThru
    }

    Write-Host "Enabling update channel" $updateRepo.name_description
    Add-XenPool -Pool $Pool -Repository $updateRepo.opaque_ref
}

<#
.SYNOPSIS
    Synchronizes the pool with the configured update channel
#>
function Sync-UpdateChannel([XenAPI.Pool]$Pool) {
    Write-Host "Synchronising with the update channel"
    Invoke-XenPool -Pool $Pool -XenAction SyncUpdates -Async -PassThru | Wait-XenTask -PassThru
}

<#
.SYNOPSIS
    Retrieves the list of available updates since the last pool synchronization
#>
function Get-Updates([XenAPI.Host]$Coordinator) {
    $task = New-XenTask -PassThru -Label "MyTrackingTask"
    $jsonPath = $env:TEMP + [System.IO.Path]::GetRandomFileName()

    Write-Host "Downloading update list"
    Receive-XenUpdates -XenHost $Coordinator.address -Path $jsonPath -TaskRef $task.opaque_ref
    $task | Wait-XenTask
    Get-Content -Raw -Path $jsonPath | ConvertFrom-Json
}

<#
.SYNOPSIS
    Installs available updates on the specified host and afterwards prints out any pending tasks
#>
function Install-Updates([XenAPI.Host]$XenHost, [String]$Hash) {
    Write-Host "Disabling host" $XenHost.name_label
    Invoke-XenHost -XenHost $XenHost -XenAction Disable

    Write-Host "Applying updates on host" $XenHost.name_label
    Invoke-XenHost -XenHost $XenHost -xenaction ApplyUpdates -Hash $Hash -Async -PassThru | Wait-XenTask

    Write-Host "Enabling host" $XenHost.name_label
    Invoke-XenHost -XenHost $XenHost -XenAction Enable

    $guidances = Get-XenHost -Ref $XenHost.opaque_ref | Select-Object -ExpandProperty pending_guidances
    Write-Host "Pending tasks:" ($guidances -join ", ")
}

#main program

Import-Module XenServerPSModule

try {
    Write-Host "Connecting to server"
    Connect-XenServer -Server $Server -UserName $Username -Password $Passwd

    $pool = Get-XenPool

    #configure the update channel
    Set-UpdateChannel -Pool $pool -RepoType ([RepoType]$Channel)

    #synchronise with the configured update channel
    $syncHash = Sync-UpdateChannel -Pool $pool

    #collect the hosts to update
    $allHosts = Get-XenHost
    $coordinator = $allHosts | Where-Object { $_.opaque_ref -eq $pool.master.opaque_ref } | Select-Object -First 1
    $supporters = $allHosts | Where-Object { $_.opaque_ref -ne $pool.master.opaque_ref }

    #get list of available updates
    $cdnUpdates = Get-Updates -Coordinator $coordinator

    if (($null -eq $cdnUpdates) -or ($null -eq $cdnUpdates.updates) -or ($cdnUpdates.updates.Length -eq 0)) {
        Write-Host "No updates found"
        return
    }

    #Print selected info on the available updates
    $theFormat = @"
Server {0}:
    Updates: {1}
    Recommended guidance: {2}
"@

    foreach ($hostUpdateInfo in $cdnUpdates.hosts) {
        $h = $allHosts | Where-Object { $_.opaque_ref -eq $hostUpdateInfo.ref } | Select-Object -First 1
        [string]::Format($theFormat, $h.name_label, ($hostUpdateInfo.updates -join ", "), ($hostUpdateInfo.recommended_guidance -join ", "))
    }

    $cdnUpdates.updates | ForEach-Object { Write-Host $_.id '***' $_.summary '***' $_.'special-info'}

    #update the hosts starting from the coordinator
    Install-Updates -XenHost $coordinator -Hash $syncHash

    foreach ($supporter in $supporters) {
        Install-Updates -XenHost $supporter -Hash $syncHash
    }
}
finally {
    Write-Host "Disconnecting all sessions"
    Get-XenSession | Disconnect-XenServer

    Remove-Module XenServerPSModule
}
