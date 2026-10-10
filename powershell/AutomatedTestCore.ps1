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

# Powershell Automated Tests

Param([Parameter(Mandatory = $true)][String]$out_xml,
    [Parameter(Mandatory = $true)][String]$svr,
    [Parameter(Mandatory = $true)][String]$usr,
    [Parameter(Mandatory = $true)][String]$passwd,
    [Parameter(Mandatory = $true)][String]$sr_svr,
    [Parameter(Mandatory = $true)][String]$sr_path,
    [Parameter(Mandatory = $false)][bool]$VerboseLogging = $true,
    [Parameter(Mandatory = $false)][bool]$WarningLogging = $true,
    [Parameter(Mandatory = $false)][bool]$ErrorLogging = $true,
    [Parameter(Mandatory = $false)][String]$ErrorActionPref = "Continue")

# Initial Setup

[Net.ServicePointManager]::SecurityProtocol = 'tls,tls11,tls12'
$BestEffort = $false
$info = $VerboseLogging
$warn = $WarningLogging
$err = $ErrorLogging
$prog = $false

$OriginalErrorActionPreference = $ErrorActionPreference
$ErrorActionPreference = $ErrorActionPref
$OriginalVerbosePreference = $VerbosePreference
$OriginalWarningPreference = $WarningPreference
$OriginalErrorPreference = $ErrorPreference

$VerbosePreference = "Continue"
$WarningPreference = "Continue"
$ErrorPreference = "Continue"
$ErrorVariable

# End Initial Setup

# Helper Functions

function log_info([String]$msg) {
    process {
        if ($info) {
            write-verbose $msg
        }
    }
}

function log_warn([String]$msg) {
    process {
        if ($warn) {
            write-warning $msg
        }
    }
}

function log_error([String]$msg) {
    process {
        if ($err) {
            write-error $msg
        }
    }
}

function prep_xml_output([String]$out_file) {
    $script:xmlDoc = New-Object System.Xml.XmlDocument
    $script:xmlDoc.AppendChild($script:xmlDoc.CreateXmlDeclaration("1.0", "UTF-8", $null)) | Out-Null
    
    $rootElement = $script:xmlDoc.CreateElement("results")
    $script:xmlDoc.AppendChild($rootElement) | Out-Null
    
    $date = Get-Date
    $testrunElement = $script:xmlDoc.CreateElement("testrun")
    $testrunElement.InnerText = "Test Run Info: PowerShell bindings test $date"
    $rootElement.AppendChild($testrunElement) | Out-Null
    
    $groupElement = $script:xmlDoc.CreateElement("group")
    $script:xmlGroupElement = $groupElement
    $rootElement.AppendChild($groupElement) | Out-Null
}

function close_xml_output([String]$out_file) {
    $script:xmlDoc.Save($out_file)
}

function add_result([String]$out_file, [String]$cmd, [String]$test_name, [Exception]$err, [DateTime]$startTime = $null, [DateTime]$endTime = $null) {
    $script:out_file = $out_file
    
    $testElement = $script:xmlDoc.CreateElement("test")
    
    $nameElement = $script:xmlDoc.CreateElement("name")
    $nameElement.InnerText = $test_name
    $testElement.AppendChild($nameElement) | Out-Null
    
    # Add timestamp elements
    if ($startTime -ne $null) {
        $startElement = $script:xmlDoc.CreateElement("startTime")
        $startElement.InnerText = $startTime.ToString("yyyy-MM-dd HH:mm:ss.fff")
        $testElement.AppendChild($startElement) | Out-Null
    }
    
    if ($endTime -ne $null) {
        $endElement = $script:xmlDoc.CreateElement("endTime")
        $endElement.InnerText = $endTime.ToString("yyyy-MM-dd HH:mm:ss.fff")
        $testElement.AppendChild($endElement) | Out-Null
        
        if ($startTime -ne $null) {
            $duration = $endTime - $startTime
            $durationElement = $script:xmlDoc.CreateElement("duration")
            $durationElement.InnerText = "$([Math]::Round($duration.TotalMilliseconds, 2))ms"
            $testElement.AppendChild($durationElement) | Out-Null
        }
    }
    
    if ($err -ne $null) {
        $stateElement = $script:xmlDoc.CreateElement("state")
        $stateElement.InnerText = "Fail"
        $testElement.AppendChild($stateElement) | Out-Null
        
        $logElement = $script:xmlDoc.CreateElement("log")
        
        $logBuilder = @()
        $logBuilder += "Cmd: '$cmd'"
        $logBuilder += "Exception: $($err.Message)"
        
        # Include inner exception chain
        if ($err.InnerException) {
            $innerExc = $err.InnerException
            while ($innerExc -ne $null) {
                $logBuilder += "Inner Exception: $($innerExc.Message)"
                $innerExc = $innerExc.InnerException
            }
        }
        
        # Include stack trace
        if ($err.StackTrace) {
            $logBuilder += "Stack Trace: $($err.StackTrace)"
        }
        
        $logElement.InnerText = $logBuilder -join "`n"
        $testElement.AppendChild($logElement) | Out-Null
    }
    else {
        $stateElement = $script:xmlDoc.CreateElement("state")
        $stateElement.InnerText = "Pass"
        $testElement.AppendChild($stateElement) | Out-Null
        
        $logElement = $script:xmlDoc.CreateElement("log")
        $testElement.AppendChild($logElement) | Out-Null
    }
    
    $script:xmlGroupElement.AppendChild($testElement) | Out-Null
}


function exec([String]$test_name, [String]$cmd, [String]$expected) {
    $startTime = Get-Date
    try {
        log_info ("Test '{0}' Started: cmd = {1}, expected = {2}" -f $test_name, $cmd, $expected)
        $result = Invoke-Expression $cmd
        $endTime = Get-Date
        
        if ($result -eq $expected) {
            add_result $script:out_xml $cmd $test_name $null $startTime $endTime
            return $true
        }
        else {
            $exc = New-Object Exception("Test '{0}' Failed: expected '{1}'; actual '{2}'" `
                    -f $test_name, $expected, $result)
            add_result $script:out_xml $cmd $test_name $exc $startTime $endTime
            $script:fails.Add($test_name, $exc)
            return $false
        }
    }
    catch [Exception] {
        $endTime = Get-Date
        add_result $script:out_xml $cmd $test_name $_.Exception $startTime $endTime
        $script:fails.Add($test_name, $_.Exception)
        return $false
    }
}

# End Helper Functions

# Connect Functions

function connect_server([String]$svr, [String]$usr, [String]$passwd) {
    log_info ("connecting to server '{0}'" -f $svr)

    # Trust all certificates. This is for test purposes only.
    # DO NOT USE -NoWarnCertificates and -NoWarnNewCertificates IN PRODUCTION CODE.
    $session = Connect-XenServer -Server $svr -UserName $usr -Password $passwd -PassThru -NoWarnCertificates -NoWarnNewCertificates

    if ($null -eq $session) {
        return $false
    }
    return $true
}

function connect_server_start_job([String]$svr, [String]$usr, [String]$passwd) {
    log_info ("connecting to server '{0}' from Start-Job" -f $svr)

    $job_script = {
        param([String]$svr, [String]$usr, [String]$passwd, [String]$profile)
        
        # Set $PROFILE so XenServerPSModule's Initialize-Environment.ps1 can use it
        $global:PROFILE = $profile

        # Trust all certificates. This is for test purposes only.
        # DO NOT USE -NoWarnCertificates and -NoWarnNewCertificates IN PRODUCTION CODE.
        $session = Connect-XenServer -Server $svr -UserName $usr -Password $passwd -PassThru -NoWarnCertificates -NoWarnNewCertificates
        if ($null -eq $session) {
            return $false
        }

        Disconnect-XenServer -Session $session
        return $true
    }

    $job = Start-Job -ScriptBlock $job_script -ArgumentList @($svr, $usr, $passwd, $PROFILE)
    $completed = Wait-Job -Job $job -Timeout 120
    if ($null -eq $completed) {
        log_warn ("Start-Job timed out for server '{0}'" -f $svr)
        Stop-Job -Job $job -ErrorAction SilentlyContinue
        Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
        return $false
    }

    $output = Receive-Job -Job $job
    Remove-Job -Job $job -Force -ErrorAction SilentlyContinue

    if ($output -contains $true) {
        return $true
    }

    return $false
}

function disconnect_server([String]$svr) {
    log_info ("disconnecting from server '{0}'" -f $svr)
    Get-XenSession -Server $svr | Disconnect-XenServer

    if ($null -eq (Get-XenSession -Server $svr)) {
        return $true
    }
    return $false
}

# End Connect Functions

# VM Functions

function destroy_vm([XenAPI.VM]$vm) {
    if ($null -eq $vm) {
        return
    }

    log_info ("destroying vm '{0}'" -f $vm.name_label)

    $vdis = @()

    foreach ($vbd in $vm.VBDs) {
        if ((Get-XenVBDProperty -Ref $vbd -XenProperty Mode) -eq [XenAPI.vbd_mode]::RW) {
            $vdis += Get-XenVBDProperty -Ref $vbd -XenProperty VDI
        }
    }

    Remove-XenVM -VM $vm -Async -PassThru | Wait-XenTask -ShowProgress

    foreach ($vdi in $vdis) {
        Remove-XenVDI -VDI $vdi -Async -PassThru | Wait-XenTask -ShowProgress
    }
}

function install_vm([String]$name, [String]$sr_name) {
    try {
        #find a windows template
        log_info "looking for a Windows template..."
        $template = @(Get-XenVM -Name 'Windows *' | Where-Object { $_.is_a_template })[0]

        log_info ("installing vm '{0}' from template '{1}'" -f $template.name_label, $name)

        #clone template
        log_info ("cloning vm '{0}' to '{1}'" -f $template.name_label, $name)
        Invoke-XenVM -VM $template -XenAction Clone -NewName $name -Async -PassThru |`
            Wait-XenTask -ShowProgress

        $vm = Get-XenVM -Name $name
        $sr = Get-XenSR -Name $sr_name
        $other_config = $vm.other_config
        $other_config["disks"] = $other_config["disks"].Replace('sr=""', 'sr="{0}"' -f $sr.uuid)

        #add cd drive
        log_info ("creating cd drive for vm '{0}'" -f $vm.name_label)
        New-XenVBD -VM $vm -VDI $null -Userdevice 3 -Bootable $false -Mode RO `
            -Type CD -Unpluggable $true -Empty $true -OtherConfig @{ } `
            -QosAlgorithmType "" -QosAlgorithmParams @{ }

        Set-XenVM -VM $vm -OtherConfig $other_config

        #provision vm
        log_info ("provisioning vm '{0}'" -f $vm.name_label)
        Invoke-XenVM -VM $vm -XenAction Provision -Async -PassThru | Wait-XenTask -ShowProgress

        return $true
    }
    catch [Exception] {
        log_info "Attempting to clean up after failed vm install..."
        try {
            $vms = Get-XenVM -Name $name
            foreach ($vm in $vms) {
                destroy_vm($vm)
            }
            log_info "...success."
        }
        catch [Exception] {
            log_warn "Clean up after failed vm install unsuccessful"
            log_info "...failed!"
        }
        throw
    }
}

function uninstall_vm([String]$name) {
    log_info ("uninstalling vm '{0}'" -f $name)

    $vms = Get-XenVM -Name $name

    foreach ($vm in $vms) {
        destroy_vm($vm)
    }

    return $true
}

function vm_can_boot($vm_name, [XenApi.Host[]] $servers) {
    $script:exceptions = @()
    foreach ($server in $servers) {
        try {
            Invoke-XenVM -Name $vm_name -XenAction AssertCanBootHere -XenHost $server
        }
        catch [Exception] {
            $script:exceptions += $_.Exception
        }
    }

    if ($exceptions.Length -lt $servers.Length) {
        return $true
    }

    log_info "No suitable place to boot VM:"

    foreach ($excep in $script:exceptions) {
        log_info ("Reason: {0}" -f $excep.Message)
    }

    return $false
}

function start_vm([String]$vm_name) {
    if (vm_can_boot $vm_name @(Get-XenHost)) {
        log_info ("starting vm '{0}'" -f $vm_name)
    }

    # even if we cant start it, attempt so we get the exception, reasons have been logged in vm_can_boot
    Invoke-XenVM -Name $vm_name -XenAction Start -Async -PassThru | Wait-XenTask -ShowProgress
    return Get-XenVM -Name $vm_name | Get-XenVMProperty -XenProperty PowerState
}

function shutdown_vm([String]$vm_name) {
    log_info ("shutting down vm '{0}'" -f $vm_name)
    Invoke-XenVM -Name $vm_name -XenAction HardShutdown -Async -PassThru | Wait-XenTask -ShowProgress
    return (Get-XenVM -Name $vm_name).power_state
}

# End VM Functions

# Host Functions

function get_coordinator() {
    $pool = Get-XenPool
    return Get-XenHost -Ref $pool.master
}

# End Host Functions

# SR Functions

function get_default_sr() {
    log_info ("getting default sr")
    $pool = Get-XenPool
    return $pool.default_SR | Get-XenSR
}

function create_nfs_sr([String]$sr_svr, [String]$sr_path, [String]$sr_name) {
    log_info ("creating sr {0} at {1}:{2}" -f $sr_name, $sr_svr, $sr_path)
    $coordinator = get_coordinator
    $sr_opq = New-XenSR -XenHost $coordinator -DeviceConfig @{ "server" = $sr_svr; "serverpath" = $sr_path; "options" = "" } `
        -PhysicalSize 0 -NameLabel $sr_name -NameDescription "" -Type "nfs" -ContentType "" `
        -Shared $true -SmConfig @{ } -Async -PassThru |`
        Wait-XenTask -ShowProgress -PassThru

    if ( $null -eq $sr_opq) {
        return $false
    }
    return $true
}

function detach_nfs_sr([String]$sr_name) {
    log_info ("destroying sr {0}" -f $sr_name)

    $pbds = Get-XenPBD
    $sr_opq = (Get-XenSR -Name $sr_name).opaque_ref

    foreach ($pbd in $pbds) {
        if (($pbd.SR.opaque_ref -eq $sr_opq) -and $pbd.currently_attached) {
            Invoke-XenPBD -PBD $pbd -XenAction Unplug
        }
    }

    Remove-XenSR -Name $sr_name -Async -PassThru | Wait-XenTask -ShowProgress

    if ($null -eq (Get-XenSR -Name $sr_name)) {
        return $true
    }
    return $false
}

# End SR Functions

# Helper Functions

function append_random_string_to([String]$toAppend, $length = 10) {
    $randomisedString = $toAppend
    $charSet = "0123456789abcdefghijklmnopqrstuvwxyz".ToCharArray()
    for ($i = 0; $i -lt $length; $i++) {
        $randomisedString += $charSet | Get-Random
    }
    return $randomisedString
}

# End Helper Functions

# Test List

$tests = @(
    @("Connect Server", "connect_server $svr $usr $passwd", $true),
    @("Connect Server Start-Job", "connect_server_start_job $svr $usr $passwd", $true),
    @("Create SR", "create_nfs_sr $sr_svr $sr_path PowerShellAutoTestSR", $true),
    @("Install VM", "install_vm PowerShellAutoTestVM PowerShellAutoTestSR", $true),
    @("Start VM", "start_vm PowerShellAutoTestVM", "Running"),
    @("Shutdown VM", "shutdown_vm PowerShellAutoTestVM", "Halted"),
    @("Uninstall VM", "uninstall_vm 'PowerShellAutoTestVM'", $true),
    @("Destroy SR", "detach_nfs_sr PowerShellAutoTestSR", $true),
    @("Disconnect Server", "disconnect_server $svr", $true)
)
# End Test List

# Main Test Execution

$complete = 0;
$max = $tests.Count;

$fails = @{ }
$script:xmlDoc = $null
$script:xmlGroupElement = $null

prep_xml_output $out_xml

$vmName = append_random_string_to "PowerShellAutoTestVM"
$srName = append_random_string_to "PowerShellAutoTestSR"

foreach ($test in $tests) {
    try {
        $success = $false

        # Add randomness to the names of the test VM and SR to
        # allow a parallel execution context
        $cmd = $test[1]
        $cmd = $cmd -replace "PowerShellAutoTestVM", $vmName
        $cmd = $cmd -replace "PowerShellAutoTestSR", $srName

        $success = exec $test[0] $cmd $test[2]
        if ($success) {
            $complete++
        }
    }
    catch [Exception] {
        # we encountered an exception in running the test before it completed
        # its already been logged, so continue
    }
}

close_xml_output $out_xml

$result = "Result: {0} completed out of {1}" -f $complete, $max;

write-host $result -f 2

if ($fails.Count -gt 0) {
    write-host "Failures:"
    $fails
}

# Determine exit code based on test results
if ($complete -eq $max -and $fails.Count -eq 0) {
    $exitCode = 0
} else {
    $exitCode = 1
}

$ErrorActionPreference = $OriginalErrorActionPreference
$VerbosePreference = $OriginalVerbosePreference
$WarningPreference = $OriginalWarningPreference
$ErrorPreference = $OriginalErrorPreference

Remove-Module XenServerPSModule

exit $exitCode

# End Main Test Execution
