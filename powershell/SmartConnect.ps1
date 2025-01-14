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


Param(
    [Parameter(Mandatory = $true)][String]$svr,
    [Parameter(Mandatory = $true)][String]$usr,
    [Parameter(Mandatory = $true)][String]$passwd
)

$Eap = $ErrorActionPreference
$ErrorActionPreference = "Stop"

Import-Module XenServerPSModule

[Net.ServicePointManager]::SecurityProtocol = 'tls,tls11,tls12'

try {
    Connect-XenServer -Server $svr -Username $usr -Password $passwd
}
catch [XenAPI.Failure] {
    # If the specified server is a pool supporter, an API error with key
    # HOST_IS_SLAVE will be raised. The second element of the error data
    # array is the IP address of the pool coordinator

    if ($_.Exception.ErrorDescription[0] -eq "HOST_IS_SLAVE") {
        
        Write-Host "The server you are trying to connect to is a pool supporter."
        Write-Host "Connecting to the pool coordinator instead..."
        
        $svr = $_.Exception.ErrorDescription[1]
        Connect-XenServer -Server $svr -Username $usr -Password $passwd
    }
}

# Print a list of servers and whether they are a coordinator or a supporter
$coordinator = Get-XenPool | Select-Object -ExpandProperty master
$allHosts = Get-XenHost

foreach ($xenHost in $allHosts) {
    if ($xenHost.opaque_ref -eq $coordinator.opaque_ref) {
        $descr = "coordinator"
    }
    else {
        $descr = "supporter"
    }

    Write-Host $xenHost.name_label ":" $descr
}

# Disconnect before finishing
Get-XenSession | Disconnect-XenServer

Remove-Module XenServerPSModule

$ErrorActionPreference = $Eap
