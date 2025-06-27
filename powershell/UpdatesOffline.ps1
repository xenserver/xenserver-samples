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
    [string]$BundlePath
)

#Initial setup
$Eap = $ErrorActionPreference
$Ep = $ErrorPreference
$ErrorActionPreference = "Stop"
$ErrorPreference = "Continue"
#End of initial setup

enum RepoType { Offline }

function Get-RepoKey([RepoType]$RepoType) {
    switch ($RepoType) {
        Offline { "offline_repo" }
    }
}

function Get-RepoDescription([RepoType]$RepoType) {
    switch ($RepoType) {
        Offline { "Offline" }
    }
}

<#
.SYNOPSIS
    Configures the pool for upload and installtion of bundle files (switch to the Offline channel)
#>
function Set-OfflineChannel {
    param(
        [XenAPI.Pool]$Pool
    )

    $key = Get-RepoKey Offline
    $descr = Get-RepoDescription Offline

    $oldEnabledRepos = $Pool.repositories | Get-XenRepository
    $offlineRepo = $oldEnabledRepos | Where-Object { $_.name_label -eq $key }

    if ($null -ne $offlineRepo) {
        Write-Host "You have already switched to the Offline channel"
        return
    }

    foreach ($rep in $oldEnabledRepos) {
        Write-Host "Disabling previous update channel" $rep.name_description
        Remove-XenPoolProperty -Pool $Pool -Repository $rep
    }

    $offlineRepo = Get-XenRepository |`
        Where-Object { $_.name_label -eq $key } |`
        Select-Object -First 1

    if ($null -eq $offlineRepo) {
        Write-Host "Introducing offline channel" $descr
        $offlineRepo = Invoke-XenRepository -XenAction IntroduceBundle -Name "dummy" `
            -NameLabel $key -NameDescription $descr -PassThru
    }

    Write-Host "Enabling channel" $offlineRepo.name_description
    Add-XenPool -Pool $Pool -Repository $offlineRepo.opaque_ref
}

<#
.SYNOPSIS
    Uploads an update bundle file (extension .xsbundle) to the pool
#>
function Send-Bundle([XenAPI.Host]$Coordinator, [string]$BundleFile) {
    $fileItem = Get-Item $BundleFile
    if (".xsbundle" -ne $fileItem.Extension.ToLower()){
        Write-Error "$BundleFile is not a valid update bundle file"
    }

    $task = New-XenTask -PassThru -Label "MyBundleUploadTask"

    Write-Host "Uploading $BundleFile to the pool"
    Send-XenBundle -XenHost $Coordinator.address -Path $BundleFile -TaskRef $task.opaque_ref

    Write-Host "Extracting update bundle and retrieving available updates..."
    $task | Wait-XenTask -ShowProgress
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
    $task | Wait-XenTask -ShowProgress
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
    Invoke-XenHost -XenHost $XenHost -xenaction ApplyUpdates -Hash $Hash -Async -PassThru | Wait-XenTask -ShowProgress

    Write-Host "Enabling host" $XenHost.name_label
    Invoke-XenHost -XenHost $XenHost -XenAction Enable

    $guidances = Get-XenHost -Ref $XenHost.opaque_ref | Select-Object -ExpandProperty pending_guidances
    Write-Host "Pending tasks:" ($guidances -join ", ")
}

#main program

Import-Module XenServerPSModule

try {
    # Trust all certificates. This is for test purposes only.
    # DO NOT USE -NoWarnCertificates and -NoWarnNewCertificates IN PRODUCTION CODE.

    Write-Host "Connecting to server"
    Connect-XenServer -Server $Server -UserName $Username -Password $Passwd -NoWarnCertificates -NoWarnNewCertificates

    $pool = Get-XenPool

    #configure the Offline channel
    Set-OfflineChannel -Pool $pool

    #collect the hosts to update
    $allHosts = Get-XenHost
    $coordinator = $allHosts | Where-Object { $_.opaque_ref -eq $pool.master.opaque_ref } | Select-Object -First 1
    $supporters = $allHosts | Where-Object { $_.opaque_ref -ne $pool.master.opaque_ref }

    #upload the update bundle file to the pool
    Send-Bundle -Coordinator $coordinator -BundleFile $BundlePath

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
    Mandatory guidance: {2}
    Recommended guidance: {3}
    Full guidance: {4}
"@

    foreach ($hostUpdateInfo in $cdnUpdates.hosts) {
        $h = $allHosts | Where-Object { $_.opaque_ref -eq $hostUpdateInfo.ref } | Select-Object -First 1
        [string]::Format($theFormat,
            $h.name_label,
            ($hostUpdateInfo.updates -join ", "),
            ($hostUpdateInfo.guidance.mandatory -join ", "),
            ($hostUpdateInfo.guidance.recommended -join ", "),
            ($hostUpdateInfo.guidance.full -join ", ")
        )
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

    $ErrorActionPreference = $Eap
    $ErrorPreference = $Ep
    Remove-Module XenServerPSModule
}
