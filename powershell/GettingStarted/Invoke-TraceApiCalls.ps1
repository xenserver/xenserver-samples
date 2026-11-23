function Invoke-TraceApiCalls {
    <#
    .SYNOPSIS
        Trace API calls.
    .DESCRIPTION
        Send a W3C trace context with your API calls, so the work the pool does for them is recorded as part
        of your application's distributed trace.

        On PowerShell 7 the module's client sends the current System.Diagnostics.Activity to the server as a
        traceparent header, so start one around the calls (in an application instrumented with
        OpenTelemetry, the current activity is already your span). Windows PowerShell 5.1's module (built for
        .NET Framework) has no Activity support: there you set the header yourself, on the session's
        RequestHeaders, before each call - the client clears them once a call is sent.
    .EXAMPLE
        Invoke-TraceApiCalls -Url https://xenserver -UserName root -Password $password
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password
    )
    $trace = $null
    if ($PSVersionTable.PSEdition -eq 'Core') {
        $trace = [System.Diagnostics.Activity]::new("trace-api-calls")
        # Recorded: the trace is sampled, which the traceparent's flags tell the pool.
        $trace.ActivityTraceFlags = [System.Diagnostics.ActivityTraceFlags]::Recorded
        $null = $trace.SetIdFormat([System.Diagnostics.ActivityIdFormat]::W3C).Start()
        $traceId, $traceparent = "$($trace.TraceId)", $trace.Id
    }
    else {
        # version 00, a 16-byte trace id, the 8-byte id of the calling span, and flags 01 (sampled)
        $bytes = New-Object byte[] 24
        [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
        $hex = -join ($bytes | ForEach-Object { $_.ToString('x2') })
        $traceId = $hex.Substring(0, 32)
        $traceparent = "00-$traceId-$($hex.Substring(32, 16))-01"
    }
    try {
        Write-Host "Trace ${traceId}: each call sends traceparent: $traceparent"
        $session = Connect-Example -Url $Url -UserName $UserName -Password $Password
        if (-not $trace) {
            $headers = New-Object 'System.Collections.Generic.Dictionary[string,string]'
            $headers.Add('traceparent', $traceparent)
            $session.RequestHeaders = $headers
        }
        $hosts = @(Get-XenHost)
        Write-Host "The pool has $($hosts.Count) hosts"
        Write-Host "OK: trace-api-calls"
        $session | Disconnect-XenServer
    }
    finally {
        if ($trace) { $trace.Stop() }
    }
}
