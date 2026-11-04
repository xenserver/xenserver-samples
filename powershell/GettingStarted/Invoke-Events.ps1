function Invoke-Events {
    <#
    .SYNOPSIS
        Event monitoring.
    .DESCRIPTION
        Subscribe to the event stream and observe a change land as an event — the mechanism for keeping a
        client's view of the pool live.
    .EXAMPLE
        Invoke-Events -Url https://xenserver -UserName root -Password $password -VmName 'web-01'
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password,
        [Parameter(Mandatory = $true)][string]$VmName
    )
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password
    # An empty token returns the current snapshot and a token; passing that token back long-polls
    # until something changes. (Get-XenEventBatch is our thin wrapper - see the top of the file.)
    $batch = Get-XenEventBatch -Session $session -Classes VM -Token "" -Timeout 1.0
    $token = $batch.token
    Write-Host "Established event token after initial snapshot."

    $vm = Get-XenVM -Name $VmName |
        Where-Object { -not $_.is_a_template -and -not $_.is_control_domain } | Select-Object -First 1
    if (-not $vm) { throw "No VM named '$VmName' was found." }
    $original = $vm.name_description
    $vm | Set-XenVM -NameDescription "changed-to-trigger-event"

    $batch = Get-XenEventBatch -Session $session -Classes VM -Token $token -Timeout 5.0
    Write-Host "Received $(@($batch.events).Count) event(s) after the change."
    $batch.events | Select-Object -First 3 | ForEach-Object { Write-Host "  - $($_.operation) $($_.class)" }

    $vm | Set-XenVM -NameDescription $original   # put it back
    Write-Host "OK: events"
    $session | Disconnect-XenServer
}

function Get-XenEventBatch {
    <#
    .SYNOPSIS
        The XenServer PowerShell module ships no event cmdlet, so this thin wrapper calls the JSON-RPC
        event.from method directly with Invoke-RestMethod (Connect-Example has already trusted the server's
        certificate, so no extra TLS setup is needed).
    .DESCRIPTION
        An empty token returns the current snapshot plus a token to watch from; passing that token back
        long-polls for changes.
    #>
    param(
        [Parameter(Mandatory = $true)]$Session,
        [Parameter(Mandatory = $true)][string[]]$Classes,
        [string]$Token = "",
        [double]$Timeout = 5.0
    )
    $body = @{
        jsonrpc = "2.0"; id = 1; method = "event.from"
        params  = @($Session.opaque_ref, $Classes, $Token, $Timeout)
    } | ConvertTo-Json -Depth 6
    $resp = Invoke-RestMethod -Uri "$($Session.Url)/jsonrpc" -Method Post -Body $body -ContentType "application/json"
    if ($resp.error) { throw "event.from failed: $($resp.error | ConvertTo-Json -Compress)" }
    return $resp.result
}
