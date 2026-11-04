function Invoke-WaitForTask {
    <#
    .SYNOPSIS
        Drive an asynchronous task.
    .DESCRIPTION
        Start a long-running operation asynchronously to get a task back immediately, then poll it to
        completion and read its result — how to drive operations without blocking.
    .EXAMPLE
        Invoke-WaitForTask -Url https://xenserver -UserName root -Password $password -TemplateName 'Rocky Linux 8'
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password,
        [Parameter(Mandatory = $true)][string]$TemplateName,
        [string]$NewVmName = "sdk-example-asynctask"
    )
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password
    # Every action has an -Async twin that returns a Task ref immediately; here we poll it by hand to
    # read the progress percentage (Wait-XenTask -ShowProgress, as vm-lifecycle uses, does this for you).
    $template = Get-XenVM -Name $TemplateName | Where-Object { $_.is_a_template } | Select-Object -First 1
    if (-not $template) { throw "No template named '$TemplateName' was found." }
    $task = $template | Invoke-XenVM -XenAction Clone -NewName $NewVmName -Async -PassThru
    $taskRef = $task.opaque_ref
    Write-Host "Started task: $((Get-XenTask -Ref $taskRef).uuid)"

    while ((Get-XenTask -Ref $taskRef).status -eq 'Pending') {
        Write-Host "  progress: $([int]((Get-XenTask -Ref $taskRef).progress * 100))%"
        Start-Sleep -Milliseconds 200
    }
    Write-Host "Task status: $((Get-XenTask -Ref $taskRef).status)"

    # The result of an object-creating task is <value>OpaqueRef:...</value>.
    $result = (Get-XenTask -Ref $taskRef).result
    $vmRef = $result.Replace("<value>", "").Replace("</value>", "").Trim()
    Write-Host "Task produced VM: $((Get-XenVM -Ref $vmRef).name_label)"

    # Tidy up.
    Get-XenVM -Ref $vmRef | Remove-XenVM
    Get-XenTask -Ref $taskRef | Remove-XenTask
    Write-Host "OK: wait-for-task"
    $session | Disconnect-XenServer
}
