function Invoke-ManageAdUsers {
    <#
    .SYNOPSIS
        Manage Active Directory users.
    .DESCRIPTION
        Join the pool to an Active Directory domain, grant an AD user access with an RBAC role, read it
        back, then tidy up.
    .EXAMPLE
        Invoke-ManageAdUsers -Url https://xenserver -UserName root -Password $password
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password,
        [string]$Domain = "",
        [string]$AdminUser = "alice",
        [string]$AdminPassword = "Password1",
        [string]$NewUser = "alice",
        [string]$Ldaps = "false"
    )
    # Needs a real, reachable AD domain controller - enable_external_auth fails at the very first call
    # (DNS/LDAP/Kerberos) without one, so Domain/AdminUser/AdminPassword have to identify a real domain
    # to join. Before joining, every host must resolve the domain (point its DNS at a domain controller)
    # and keep its clock close to the DC's (Kerberos). Current Windows DCs want LDAPS (Ldaps="true"),
    # which also needs the pool to trust the DC's CA certificate (pool.install_trusted_certificate with
    # purpose "ldaps"). NewUser is the account to grant a role to; its subject identity is looked up
    # against the directory, so it has to be a real account there too. A pool already joined to this
    # domain is used as it is - and left joined. The defaults are placeholders: pass your own domain,
    # administrator account and user.
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password
    # The compiled module's AD cmdlets are awkward to script, so the AD calls go over JSON-RPC (the module
    # already trusts the server cert after Connect) — the same approach as the events example.
    function Rpc([string]$Method, [object[]]$P) {
        $body = @{ jsonrpc = "2.0"; id = 1; method = $Method; params = @($session.opaque_ref) + $P } | ConvertTo-Json -Depth 8
        $r = Invoke-RestMethod -Uri "$($session.Url)/jsonrpc" -Method Post -Body $body -ContentType "application/json"
        if ($r.error) { throw "$Method failed: $($r.error | ConvertTo-Json -Compress)" }
        $r.result
    }

    $pool = @(Rpc "pool.get_all" @())[0]
    $coordinator = Rpc "pool.get_master" @($pool)
    $alreadyJoined = $Domain -and (Rpc "host.get_external_auth_type" @($coordinator)) -eq "AD" `
        -and (Rpc "host.get_external_auth_service_name" @($coordinator)) -ieq $Domain
    if ($alreadyJoined) {
        Write-Host "Already joined to domain: $Domain"
    } else {
        Rpc "pool.enable_external_auth" @($pool, @{ user = $AdminUser; pass = $AdminPassword; ldaps = $Ldaps }, $Domain, "AD") | Out-Null
        Write-Host "Joined domain: $(if ($Domain) { $Domain } else { "(none given)" })"
    }

    # Add an AD user as a subject and grant it the pool-admin role (found via the Get-XenRole cmdlet,
    # simpler/more idiomatic than filtering Get-XenRole's own roles - matches what
    # `xe subject-role-add role-name=` does server-side).
    $subjectName = if ($Domain) { "$NewUser@$Domain" } else { $NewUser }
    $sid = Rpc "auth.get_subject_identifier" @($subjectName)
    $info = Rpc "auth.get_subject_information_from_identifier" @($sid)
    # other_config/roles are accepted here but discarded by real xapi (it re-derives other_config from
    # AD itself, and roles isn't a settable constructor field) - subject.add_to_roles below is the call
    # that actually matters.
    $subject = Rpc "subject.create" @(@{ subject_identifier = $sid; other_config = @{}; roles = @() })
    $adminRole = Get-XenRole -Name 'pool-admin' | Select-Object -First 1
    Rpc "subject.add_to_roles" @($subject, $adminRole.opaque_ref) | Out-Null
    Write-Host "Added subject $($info.'subject-displayname') ($($info.'subject-name')) as pool-admin"

    # Revoking access does not end sessions the user already has: logging the subject out is a separate
    # act, and the one that actually gets them off the pool now rather than at next login.
    $loggedIn = @(Rpc "session.get_all_subject_identifiers" @())
    Write-Host "Logged-in subjects: $($loggedIn.Count)"
    Rpc "session.logout_subject_identifier" @($sid) | Out-Null
    Write-Host "  logged out $($info.'subject-name')"

    # Tidy up (remove the role assignment, then the subject).
    Rpc "subject.remove_from_roles" @($subject, $adminRole.opaque_ref) | Out-Null
    Rpc "subject.destroy" @($subject) | Out-Null
    if (-not $alreadyJoined) {
        # Leave the way it was found. Passing the admin credentials also removes the pool's computer
        # accounts from the directory; with {} they stay behind in AD.
        Rpc "pool.disable_external_auth" @($pool, @{ user = $AdminUser; pass = $AdminPassword }) | Out-Null
    }
    Write-Host "OK: manage-ad-users"
    $session | Disconnect-XenServer
}
