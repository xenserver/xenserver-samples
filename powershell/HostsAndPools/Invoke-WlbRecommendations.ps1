function Invoke-WlbRecommendations {
    <#
    .SYNOPSIS
        Read workload-balancing recommendations.
    .DESCRIPTION
        Point the pool at a workload-balancing appliance, read its placement recommendations for the pool
        and for one VM, then disconnect it.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password,
        [string]$VmName = "web-01",
        [string]$WlbHostPort = "wlb.example:8012",
        [string]$WlbUsername = "wlbuser",
        [string]$WlbPassword = "wlbpass",
        [string]$WlbCertificate = ""
    )
    # Needs a real, reachable WLB appliance: InitializeWlb makes a synchronous HTTP call to it and raises
    # WLB_CONNECTION_REFUSED/WLB_CONNECTION_RESET if it can't connect - there is no way to fake this with
    # a placeholder. WlbHostPort is host:port, with NO URL scheme - that is the real wire format
    # (xe pool-initialize-wlb wlb_url="10.x.x.x:30601" ...), not a URL.
    #
    # The pool checks the appliance's TLS certificate (wlb_verify_cert), and only against the
    # certificates installed with -XenAction CertificateInstall - not InstallTrustedCertificate's. A
    # fresh appliance has a self-signed one, so pass it as WlbCertificate (a PEM file): without it
    # InitializeWlb fails with INTERNAL_ERROR "Connection failed: configuration failed." and no hint
    # that the certificate is the reason.
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password
    $pool = Get-XenPool | Select-Object -First 1

    $certName = ""
    if ($WlbCertificate) {
        $certName = "sdk-example-wlb.pem"
        Invoke-XenPool -Ref $pool.opaque_ref -XenAction CertificateInstall `
            -NameParam $certName -Cert (Get-Content -Raw $WlbCertificate)   # pool-wide: no -Pool/-Ref target
    }
    Invoke-XenPool -Ref $pool.opaque_ref -XenAction InitializeWlb `
        -WlbUrl $WlbHostPort -WlbUsername $WlbUsername -WlbPassword $WlbPassword `
        -XenserverUsername $UserName -XenserverPassword $Password
    try {
        # Initializing connects the pool to the appliance but leaves balancing off: every WLB call
        # after this would fail WLB_DISABLED until it's switched on.
        Set-XenPool -Pool $pool -WlbEnabled $true
        Write-Host "WLB: $((Get-XenPool | Select-Object -First 1).wlb_url)"

        # Read BY POSITION, and the two calls do not share a shape. The pool's are keyed by VM and say
        # where to move it: [0] "wlb", [1] the destination host's UUID (a uuid, not a ref), [2] and [3]
        # ids, [4] the reason.
        # -PassThru: without it Invoke-Xen* runs the action and emits nothing, so a value-returning
        # action looks like it returned null.
        $poolRecs = Invoke-XenPool -Ref $pool.opaque_ref -XenAction RetrieveWlbRecommendations -PassThru
        foreach ($entry in $poolRecs.GetEnumerator()) {
            $fields = @($entry.Value)
            $name = (Get-XenVM -Ref $entry.Key).name_label
            Write-Host "  move $name -> host $($fields[1]) ($($fields[4]))"
        }

        # A VM's own are keyed by host and star-rate each destination: [0] "wlb", [1] the rating -
        # higher is better (a real appliance rated hosts 6.1 here, so not capped at five). Right
        # after connecting, the appliance is still discovering the pool and answers
        # WLB_INTERNAL_ERROR 4024 ("Pool discovery has not been started"), 4025 ("... has not been
        # completed"), then 4016 ("WLB does not have current metrics") - keep asking for a while.
        $vm = Get-XenVM -Name $VmName
        $deadline = (Get-Date).AddMinutes(10)
        while ($true) {
            try { $vmRecs = Invoke-XenVM -Ref $vm.opaque_ref -XenAction RetrieveWlbRecommendations -PassThru; break }
            catch {
                $ex = $_.Exception
                while ($ex -and -not $ex.ErrorDescription) { $ex = $ex.InnerException }
                if (-not ($ex -and $ex.ErrorDescription -and $ex.ErrorDescription[0] -eq "WLB_INTERNAL_ERROR" `
                        -and $ex.ErrorDescription[1] -in "4024", "4025", "4016") -or (Get-Date) -gt $deadline) {
                    throw
                }
                Start-Sleep -Seconds 15
            }
        }
        foreach ($entry in $vmRecs.GetEnumerator()) {
            $fields = @($entry.Value)
            Write-Host "  $((Get-XenHost -Ref $entry.Key).name_label) rated $($fields[1])"
        }

        # The appliance's own settings are read and written as one flat map of strings. Send a nightly
        # reporting schedule, then read the configuration back to confirm it took.
        Invoke-XenPool -Ref $pool.opaque_ref -XenAction SendWlbConfiguration -Config @{ ReportingCronString = "0 3 * * *" }
        $config = Invoke-XenPool -Ref $pool.opaque_ref -XenAction RetrieveWlbConfiguration -PassThru
        $pairs = $config.GetEnumerator() | Sort-Object Key | ForEach-Object { "$($_.Key)=$($_.Value)" }
        Write-Host "  appliance configuration: $($pairs -join ', ')"
    }
    finally {
        # Disconnect from the appliance however the above went, or the pool stays attached to it.
        Invoke-XenPool -Ref $pool.opaque_ref -XenAction DeconfigureWlb
        if ($certName) { Invoke-XenPool -Ref $pool.opaque_ref -XenAction CertificateUninstall -NameParam $certName }
    }
    Write-Host "OK: wlb-recommendations"
    $session | Disconnect-XenServer
}
