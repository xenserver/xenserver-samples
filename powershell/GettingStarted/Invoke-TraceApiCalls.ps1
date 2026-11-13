function Invoke-TraceApiCalls {
    <#
    .SYNOPSIS
        Trace API calls.
    .DESCRIPTION
        Send a W3C trace context with your API calls, so the work the pool does for them is recorded as part
        of your application's distributed trace.

        The module's client sends the current System.Diagnostics.Activity to the server as a traceparent
        header, so start one around the calls (in an application instrumented with OpenTelemetry, the
        current activity is already your span).
    .EXAMPLE
        Invoke-TraceApiCalls -Url https://xenserver -UserName root -Password $password
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password
    )
    $trace = [System.Diagnostics.Activity]::new("trace-api-calls")
    # Recorded: the trace is sampled, which the traceparent's flags tell the pool.
    $trace.ActivityTraceFlags = [System.Diagnostics.ActivityTraceFlags]::Recorded
    $null = $trace.SetIdFormat([System.Diagnostics.ActivityIdFormat]::W3C).Start()
    try {
        Write-Host "Trace $($trace.TraceId): each call sends traceparent: $($trace.Id)"
        $session = Connect-Example -Url $Url -UserName $UserName -Password $Password
        $hosts = @(Get-XenHost)
        Write-Host "The pool has $($hosts.Count) hosts"
        Write-Host "OK: trace-api-calls"
        $session | Disconnect-XenServer
    }
    finally {
        $trace.Stop()
    }
}
