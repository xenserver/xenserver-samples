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
    [Parameter(Mandatory = $true)][String]$passwd)

### Connect to a server

Import-Module XenServerPSModule

[Net.ServicePointManager]::SecurityProtocol = 'tls,tls11,tls12'

# Trust all certificates. This is for test purposes only.
# DO NOT USE -NoWarnCertificates and -NoWarnNewCertificates IN PRODUCTION CODE.
Connect-XenServer -Server $svr -UserName $usr -Password $passwd -NoWarnCertificates -NoWarnNewCertificates

try{
    ### Get host RRDs

    $trackDataReceived = [XenAPI.HTTP+DataCopiedDelegate] {
        param($bytes);
        Write-Host "Bytes received: $bytes"
    }

    $path = $env:TEMP + "\rrd.xml"
    Receive-XenHostRrd -XenHost $svr -Path $path -DataCopiedDelegate $trackDataReceived
}
finally{
    ### Disconnect before finishing
    Get-XenSession | Disconnect-XenServer

    Remove-Module XenServerPSModule
}
