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


Param([Parameter(Mandatory = $true)][String]$svr,
    [Parameter(Mandatory = $true)][String]$usr,
    [Parameter(Mandatory = $true)][String]$passwd,
    [Parameter(Mandatory = $true)][String]$updatePath)

### Connect to a server

Import-Module XenServerPSModule

[Net.ServicePointManager]::SecurityProtocol = 'tls,tls11,tls12'

# Trust all certificates. This is for test purposes only.
# DO NOT USE -NoWarnCertificates and -NoWarnNewCertificates IN PRODUCTION CODE.
Connect-XenServer -Server $svr -UserName $usr -Password $passwd -NoWarnCertificates -NoWarnNewCertificates

try{
    ### Find the default SR to upload the update
    $sr = Get-XenPool | Select-Object -ExpandProperty default_SR | Get-XenSR

    ### The update will be uploaded as a raw image, so we need to create the target VDI first

    $file = [System.IO.FileInfo]$updatePath

    $vdiRef = New-XenVDI -ReadOnly $false -SR $sr.opaque_ref -VirtualSize $file.Length `
        -NameLabel $file.BaseName -NameDescription "temporary disk" `
        -Sharable $false -Type user -SmConfig @{ "vmhint" = "" } `
        -OtherConfig @{"supp_pack_iso" = "true"} -Async -PassThru |`
        Wait-XenTask -ShowProgress -PassThru

    ### Upload the update

    $trackProgress = [XenAPI.HTTP+UpdateProgressDelegate] {
        param($percent);
        Write-Progress -Activity "Uploading patch..." -PercentComplete $percent }

    Import-XenRawVdi -XenHost $svr -Path $updatePath -ProgressDelegate $trackProgress -Vdi $vdiRef

    $update = Invoke-XenPoolUpdate -XenAction Introduce -Name "dummy" -Vdi $vdiRef -PassThru

    ### Install the update on the pool hosts and display any post-update guidance

    Invoke-XenPoolUpdate -XenAction PoolApply -PoolUpdate $update -Async -PassThru |`
        Wait-XenTask -ShowProgress
    
    Write-Host "Post-update tasks:" ($update.after_apply_guidance -join ", ")
}
finally{

    ### Delete the temporary disk
    try {
        if ($null -ne $vdiRef) {
            Remove-XenVdi -Ref $vdiRef
        }
    }
    catch{
        Write-Warning "Failed to clean up the uploaded update"
    }

    ### Disconnect before finishing
    Get-XenSession | Disconnect-XenServer

    Remove-Module XenServerPSModule
}
