function Invoke-ErrorHandling {
    <#
    .SYNOPSIS
        Handle an API error.
    .DESCRIPTION
        Catch an API failure and inspect its error code and parameters — the shape of every error the API
        returns, and how to react to it robustly.
    .EXAMPLE
        Invoke-ErrorHandling -Url https://xenserver -UserName root -Password $password
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password
    )
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password
    # XenAPI errors surface as a failure whose ErrorDescription is [CODE, param1, param2, ...]. Any
    # cmdlet that reaches the server can raise one - here we deliberately act on a VM UUID that doesn't
    # exist. The module may wrap the failure, so walk the InnerException chain to the ErrorDescription.
    try {
        Set-XenVM -Uuid (New-Guid).Guid -NameLabel "will-not-apply"
        Write-Host "unexpected: no error"
    }
    catch {
        $ex = $_.Exception
        while ($ex -and -not $ex.ErrorDescription) { $ex = $ex.InnerException }
        if ($ex -and $ex.ErrorDescription) { Write-Host "Caught expected failure: $($ex.ErrorDescription[0])" }
        else { Write-Host "Caught expected failure: $($_.Exception.Message)" }
    }
    Write-Host "OK: error-handling"
    $session | Disconnect-XenServer
}
