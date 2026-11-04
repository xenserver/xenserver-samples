<!-- Generated from workflows.json, the example sources and a run of each example. Edit those, not this file. -->

# Manage Active Directory users

Join the pool to an Active Directory domain, grant an AD user access with an RBAC role, read it back, then tidy up.

**Requires:** an Active Directory domain.

Workflow `manage-ad-users`. [All workflows](README.md) · [Connecting](connecting.md)

## C# (.NET)

Source: [`csharp/SecurityAndAccess/ManageAdUsers.cs`](../../csharp/SecurityAndAccess/ManageAdUsers.cs)

```csharp
/// <summary> Join the pool to an Active Directory domain, grant an AD user access with an RBAC role, read
/// it back, then tidy up. </summary> <example> <code> Workflows.ManageAdUsers("https://xenserver",
/// "root", password); </code> </example> <remarks> Join AD, add a user as a subject with an RBAC role,
/// read it back, then tidy up. Needs a real, reachable AD domain controller - enable_external_auth fails
/// at the very first call (DNS/LDAP/Kerberos) without one, so domain/admin_user/admin_password have to
/// identify a real domain to join. Before joining, every host must resolve the domain (point its DNS at a
/// domain controller) and keep its clock close to the DC's (Kerberos). Current Windows DCs want LDAPS
/// (ldaps="true"), which also needs the pool to trust the DC's CA certificate
/// (Pool.install_trusted_certificate with purpose "ldaps"). new_user is the account to grant a role to;
/// its subject identity is looked up against the directory, so it has to be a real account there too. A
/// pool already joined to this domain is used as it is - and left joined. The defaults are placeholders:
/// pass your own domain, administrator account and user. </remarks>
public static void ManageAdUsers(string url, string user, string password, string domain = "",
    string adminUser = "alice", string adminPassword = "Password1", string newUser = "alice",
    string ldaps = "false")
{
    var session = Connect(url, user, password);
    var pool = Pool.get_all(session)[0].opaque_ref;
    var coordinator = Pool.get_master(session, pool).opaque_ref;
    var alreadyJoined = !string.IsNullOrEmpty(domain)
        && Host.get_external_auth_type(session, coordinator) == "AD"
        && string.Equals(Host.get_external_auth_service_name(session, coordinator), domain,
            StringComparison.OrdinalIgnoreCase);
    if (alreadyJoined)
    {
        Console.WriteLine($"Already joined to domain: {domain}");
    }
    else
    {
        Pool.enable_external_auth(session, pool,
            new Dictionary<string, string> { ["user"] = adminUser, ["pass"] = adminPassword, ["ldaps"] = ldaps },
            domain, "AD");
        Console.WriteLine($"Joined domain: {(string.IsNullOrEmpty(domain) ? "(none given)" : domain)}");
    }

    var subjectName = string.IsNullOrEmpty(domain) ? newUser : $"{newUser}@{domain}";
    var sid = Auth.get_subject_identifier(session, subjectName);
    var info = Auth.get_subject_information_from_identifier(session, sid);
    // other_config/roles are accepted here but discarded by real xapi (it re-derives other_config
    // from AD itself, and roles isn't a settable constructor field) - subject.add_to_roles below is
    // the call that actually matters.
    var subject = Subject.create(session, new Subject
    {
        subject_identifier = sid,
        other_config = new Dictionary<string, string>(),
        roles = new List<XenRef<Role>>(),
    }).opaque_ref;
    var adminRole = Role.get_by_name_label(session, "pool-admin")[0];
    Subject.add_to_roles(session, subject, adminRole);
    Console.WriteLine($"Added subject {info["subject-displayname"]} ({info["subject-name"]}) as " +
        string.Join(", ", Subject.get_roles(session, subject).Select(r => Role.get_name_label(session, r.opaque_ref))));

    // Revoking access does not end sessions the user already has: logging the subject out is a
    // separate act, and the one that actually gets them off the pool now rather than at next login.
    Console.WriteLine($"Logged-in subjects: {Session.get_all_subject_identifiers(session).Length}");
    Session.logout_subject_identifier(session, sid);
    Console.WriteLine($"  logged out {info["subject-name"]}");

    Subject.remove_from_roles(session, subject, adminRole);
    Subject.destroy(session, subject);
    if (!alreadyJoined)
    {
        // Leave the way it was found. Passing the admin credentials also removes the pool's
        // computer accounts from the directory; with {} they stay behind in AD.
        Pool.disable_external_auth(session, pool,
            new Dictionary<string, string> { ["user"] = adminUser, ["pass"] = adminPassword });
    }
    Console.WriteLine("OK: manage-ad-users");
    session.logout();
}
```

<details><summary>Sample output</summary>

```text
Joined domain: (none given)
Added subject Alice Admin (alice) as pool-admin
Logged-in subjects: 0
  logged out alice
OK: manage-ad-users
```

</details>

## Python

Source: [`python/security_and_access/manage_ad_users.py`](../../python/security_and_access/manage_ad_users.py)

```python
"""Manage Active Directory users.

Join the pool to an Active Directory domain, grant an AD user access with an RBAC role, read it
back, then tidy up.
"""

from connection import connect


def manage_ad_users(url, username, password, domain="", admin_user="alice",
                     admin_password="Password1", new_user="alice", ldaps="false"):
    """Join AD, add a user as a subject with an RBAC role, read it back, then tidy up.

    Needs a real, reachable AD domain controller - enable_external_auth fails at the very first
    call (DNS/LDAP/Kerberos) without one, so domain/admin_user/admin_password have to identify a
    real domain to join. Before joining, every host must resolve the domain (point its DNS at a
    domain controller) and keep its clock close to the DC's (Kerberos). Current Windows DCs want
    LDAPS (ldaps="true"), which also needs the pool to trust the DC's CA certificate
    (pool.install_trusted_certificate with purpose "ldaps"). new_user is the account to grant a
    role to; its subject identity is looked up against the directory, so it has to be a real
    account there too. A pool already joined to this domain is used as it is - and left joined.
    The defaults are placeholders: pass your own domain, administrator account and user."""
    session = connect(url, username, password)
    pool = session.xenapi.pool.get_all()[0]
    coordinator = session.xenapi.pool.get_master(pool)
    already_joined = (domain and session.xenapi.host.get_external_auth_type(coordinator) == "AD"
                      and session.xenapi.host.get_external_auth_service_name(coordinator).lower()
                      == domain.lower())
    if already_joined:
        print("Already joined to domain: %s" % domain)
    else:
        session.xenapi.pool.enable_external_auth(
            pool, {"user": admin_user, "pass": admin_password, "ldaps": ldaps}, domain, "AD")
        print("Joined domain: %s" % (domain or "(none given)"))

    subject_name = "%s@%s" % (new_user, domain) if domain else new_user
    sid = session.xenapi.auth.get_subject_identifier(subject_name)
    info = session.xenapi.auth.get_subject_information_from_identifier(sid)
    # other_config/roles are accepted here but discarded by real xapi (it re-derives other_config
    # from AD itself, and roles isn't a settable constructor field) - subject.add_to_roles below is
    # the call that actually matters.
    subject = session.xenapi.subject.create({"subject_identifier": sid, "other_config": {}, "roles": []})
    admin_role = session.xenapi.role.get_by_name_label("pool-admin")[0]
    session.xenapi.subject.add_to_roles(subject, admin_role)
    roles = [session.xenapi.role.get_name_label(r) for r in session.xenapi.subject.get_roles(subject)]
    print("Added subject %s (%s) as %s"
          % (info["subject-displayname"], info["subject-name"], ", ".join(roles)))

    # Revoking access does not end sessions the user already has: logging the subject out is a
    # separate act, and the one that actually gets them off the pool now rather than at next login.
    print("Logged-in subjects: %d" % len(session.xenapi.session.get_all_subject_identifiers()))
    session.xenapi.session.logout_subject_identifier(sid)
    print("  logged out %s" % info["subject-name"])

    session.xenapi.subject.remove_from_roles(subject, admin_role)
    session.xenapi.subject.destroy(subject)
    if not already_joined:
        # Leave the way it was found. Passing the admin credentials also removes the pool's computer
        # accounts from the directory; with {} they stay behind in AD.
        session.xenapi.pool.disable_external_auth(pool, {"user": admin_user, "pass": admin_password})
    print("OK: manage-ad-users")
    session.logout()
```

<details><summary>Sample output</summary>

```text
Joined domain: (none given)
Added subject Alice Admin (alice) as pool-admin
Logged-in subjects: 0
  logged out alice
OK: manage-ad-users
```

</details>

## Java

Source: [`java/src/main/java/com/xenserver/samples/securityandaccess/ManageAdUsers.java`](../../java/src/main/java/com/xenserver/samples/securityandaccess/ManageAdUsers.java)

```java
package com.xenserver.samples.securityandaccess;

import com.xensource.xenapi.Auth;
import com.xensource.xenapi.Connection;
import com.xensource.xenapi.Host;
import com.xensource.xenapi.Pool;
import com.xensource.xenapi.Role;
import com.xensource.xenapi.Session;
import com.xensource.xenapi.Subject;

import static com.xenserver.samples.PoolConnection.connect;

public final class ManageAdUsers {
    private ManageAdUsers() {
    }

    /**
     * Manage Active Directory users.
     *
     * <p>Join the pool to an Active Directory domain, grant an AD user access with an RBAC role, read it
     * back, then tidy up.
     *
     * <p>Join AD, add a user as a subject with an RBAC role, read it back, then tidy up.
     *
     * <p>Needs a real, reachable AD domain controller - enableExternalAuth fails at the very first call
     * (DNS/LDAP/Kerberos) without one, so domain/adminUser/adminPassword have to identify a real domain to
     * join. Before joining, every host must resolve the domain (point its DNS at a domain controller) and
     * keep its clock close to the DC's (Kerberos). Current Windows DCs want LDAPS (ldaps="true"), which
     * also needs the pool to trust the DC's CA certificate (pool.installTrustedCertificate with purpose
     * "ldaps"). newUser is the account to grant a role to; its subject identity is looked up against the
     * directory, so it has to be a real account there too. A pool already joined to this domain is used as
     * it is - and left joined. The defaults are placeholders: pass your own domain, administrator account
     * and user.
     *
     * <p>Run it:
     *
     * <pre>{@code
     * ManageAdUsers.run("https://xenserver", "root", password, "", "alice", "Password1", "alice", "false");
     * }</pre>
     */
    public static void run(String url, String user, String password, String domain,
            String adminUser, String adminPassword, String newUser, String ldaps) throws Exception {
        Connection conn = connect(url, user, password);
        try {
            Pool pool = Pool.getAll(conn).iterator().next();
            Host coordinator = pool.getMaster(conn);
            boolean alreadyJoined = !domain.isEmpty()
                    && "AD".equals(coordinator.getExternalAuthType(conn))
                    && coordinator.getExternalAuthServiceName(conn).equalsIgnoreCase(domain);
            if (alreadyJoined) {
                System.out.println("Already joined to domain: " + domain);
            } else {
                java.util.Map<String, String> config = new java.util.HashMap<>();
                config.put("user", adminUser);
                config.put("pass", adminPassword);
                config.put("ldaps", ldaps);
                pool.enableExternalAuth(conn, config, domain, "AD");
                System.out.println("Joined domain: " + (!domain.isEmpty() ? domain : "(none given)"));
            }

            String subjectName = !domain.isEmpty() ? newUser + "@" + domain : newUser;
            String sid = Auth.getSubjectIdentifier(conn, subjectName);
            java.util.Map<String, String> info = Auth.getSubjectInformationFromIdentifier(conn, sid);
            // otherConfig/roles are accepted here but discarded by real xapi (it re-derives otherConfig
            // from AD itself, and roles isn't a settable constructor field) - subject.addToRoles below is
            // the call that actually matters.
            Subject.Record srec = new Subject.Record();
            srec.subjectIdentifier = sid;
            srec.otherConfig = new java.util.HashMap<>();
            Subject subject = Subject.create(conn, srec);

            // Resolve the "pool-admin" role with role.getByNameLabel (simpler/more idiomatic than
            // filtering getAllRecords, matches what `xe subject-role-add role-name=` does server-side).
            Role admin = Role.getByNameLabel(conn, "pool-admin").iterator().next();
            subject.addToRoles(conn, admin);
            StringBuilder roles = new StringBuilder();
            for (Role r : subject.getRoles(conn)) roles.append(r.getNameLabel(conn)).append(" ");
            System.out.println("Added subject " + info.get("subject-displayname") + " (" + info.get("subject-name")
                    + ") as " + roles.toString().trim());

            // Revoking access does not end sessions the user already has: logging the subject out is a
            // separate act, and the one that actually gets them off the pool now rather than at next login.
            System.out.println("Logged-in subjects: " + Session.getAllSubjectIdentifiers(conn).size());
            Session.logoutSubjectIdentifier(conn, sid);
            System.out.println("  logged out " + info.get("subject-name"));

            subject.removeFromRoles(conn, admin);
            subject.destroy(conn);
            if (!alreadyJoined) {
                // Leave the way it was found. Passing the admin credentials also removes the pool's
                // computer accounts from the directory; with {} they stay behind in AD.
                java.util.Map<String, String> leaveConfig = new java.util.HashMap<>();
                leaveConfig.put("user", adminUser);
                leaveConfig.put("pass", adminPassword);
                pool.disableExternalAuth(conn, leaveConfig);
            }
            System.out.println("OK: manage-ad-users");
        } finally {
            Session.logout(conn);
        }
    }
}
```

<details><summary>Sample output</summary>

```text
Joined domain: (none given)
Added subject Alice Admin (alice) as pool-admin
Logged-in subjects: 0
  logged out alice
OK: manage-ad-users
```

</details>

## Go

Source: [`go/manage_ad_users.go`](../../go/manage_ad_users.go)

```go
package main

import (
	"fmt"
	"strings"

	"go/xenapi"
)

// manageAdUsers joins AD, adds a user as a subject with an RBAC role, reads it back, then tidies
// up. Needs a real, reachable AD domain controller - EnableExternalAuth fails at the very first
// call (DNS/LDAP/Kerberos) without one, so domain/adminUser/adminPassword have to identify a real
// domain to join. Before joining, every host must resolve the domain (point its DNS at a domain
// controller) and keep its clock close to the DC's (Kerberos). Current Windows DCs want LDAPS
// (ldaps="true"), which also needs the pool to trust the DC's CA certificate
// (xenapi.Pool.InstallTrustedCertificate with purpose "ldaps"). newUser is the account to grant a
// role to; its subject identity is looked up against the directory, so it has to be a real account
// there too. A pool already joined to this domain is used as it is - and left joined. The defaults
// are placeholders: pass your own domain, administrator account and user.
func manageAdUsers(url, user, password, domain, adminUser, adminPassword, newUser, ldaps string) {
	session := connect(url, user, password)

	pools, err := xenapi.Pool.GetAll(session)
	check(err)
	pool := pools[0]
	coordinator, err := xenapi.Pool.GetMaster(session, pool)
	check(err)
	authType, err := xenapi.Host.GetExternalAuthType(session, coordinator)
	check(err)
	authDomain, err := xenapi.Host.GetExternalAuthServiceName(session, coordinator)
	check(err)
	alreadyJoined := domain != "" && authType == "AD" && strings.EqualFold(authDomain, domain)
	if alreadyJoined {
		fmt.Printf("Already joined to domain: %s\n", domain)
	} else {
		check(xenapi.Pool.EnableExternalAuth(session, pool,
			map[string]string{"user": adminUser, "pass": adminPassword, "ldaps": ldaps}, domain, "AD"))
		if domain != "" {
			fmt.Printf("Joined domain: %s\n", domain)
		} else {
			fmt.Println("Joined domain: (none given)")
		}
	}

	subjectName := newUser
	if domain != "" {
		subjectName = newUser + "@" + domain
	}
	sid, err := xenapi.Auth.GetSubjectIdentifier(session, subjectName)
	check(err)
	info, err := xenapi.Auth.GetSubjectInformationFromIdentifier(session, sid)
	check(err)
	subject, err := xenapi.Subject.Create(session, xenapi.SubjectRecord{SubjectIdentifier: sid, OtherConfig: info})
	check(err)

	// role.get_by_name_label is simpler/more idiomatic than filtering get_all_records, and matches
	// what `xe subject-role-add role-name=` does server-side.
	roleRefs, err := xenapi.Role.GetByNameLabel(session, "pool-admin")
	check(err)
	admin := roleRefs[0]
	check(xenapi.Subject.AddToRoles(session, subject, admin))
	assigned, err := xenapi.Subject.GetRoles(session, subject)
	check(err)
	names := ""
	for _, r := range assigned {
		n, _ := xenapi.Role.GetNameLabel(session, r)
		names += n + " "
	}
	fmt.Printf("Added subject %s (%s) as %s\n",
		info["subject-displayname"], info["subject-name"], strings.TrimSpace(names))

	// Revoking access does not end sessions the user already has: logging the subject out is a separate
	// act, and the one that actually gets them off the pool now rather than at next login.
	loggedIn, err := session.GetAllSubjectIdentifiers()
	check(err)
	fmt.Printf("Logged-in subjects: %d\n", len(loggedIn))
	check(session.LogoutSubjectIdentifier(sid))
	fmt.Printf("  logged out %s\n", info["subject-name"])

	check(xenapi.Subject.RemoveFromRoles(session, subject, admin))
	check(xenapi.Subject.Destroy(session, subject))
	if !alreadyJoined {
		// Leave the way it was found. Passing the admin credentials also removes the pool's computer
		// accounts from the directory; with {} they stay behind in AD.
		check(xenapi.Pool.DisableExternalAuth(session, pool,
			map[string]string{"user": adminUser, "pass": adminPassword}))
	}
	fmt.Println("OK: manage-ad-users")
	session.Logout()
}
```

<details><summary>Sample output</summary>

```text
Joined domain: (none given)
Added subject Alice Admin (alice) as pool-admin
Logged-in subjects: 0
  logged out alice
OK: manage-ad-users
```

</details>

## PowerShell

Source: [`powershell/SecurityAndAccess/Invoke-ManageAdUsers.ps1`](../../powershell/SecurityAndAccess/Invoke-ManageAdUsers.ps1)

```powershell
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
```

<details><summary>Sample output</summary>

```text
Joined domain: (none given)
Added subject Alice Admin (alice) as pool-admin
Logged-in subjects: 0
  logged out alice
OK: manage-ad-users
```

</details>

## xe CLI

Source: [`cli/security-and-access/manage-ad-users.sh`](../../cli/security-and-access/manage-ad-users.sh)

```bash
# Manage Active Directory users.
#
# Join the pool to an Active Directory domain, grant an AD user access with an RBAC role, read it back, then
# tidy up.
#
# Run it:
#   ./workflows.sh manage-ad-users https://xenserver root "$password"
#
# Optional key=value arguments (default):
#   domain ("")
#   admin_user (alice)
#   admin_password (Password1)
#   new_user (alice)
#   ldaps (false)

# Needs a real, reachable AD domain controller - pool-enable-external-auth fails at the very first call
# (DNS/LDAP/Kerberos) without one, so domain/admin_user/admin_password have to identify a real domain to
# join. Before joining, every host must resolve the domain (point its DNS at a domain controller) and
# keep its clock close to the DC's (Kerberos). Current Windows DCs want LDAPS (ldaps=true), which also
# needs the pool to trust the DC's CA certificate (pool-certificate-install ... purpose=ldaps, i.e.
# install_trusted_certificate). new_user is the account to grant a role to; its subject identity is
# looked up against the directory, so it has to be a real account there too. A pool already joined to
# this domain is used as it is - and left joined. The defaults are placeholders: pass your own domain,
# administrator account and user.
manage_ad_users() {
    local domain admin_user admin_password new_user ldaps subject_name master auth_type auth_service already_joined=false
    domain=$(param domain "")
    admin_user=$(param admin_user "alice")
    admin_password=$(param admin_password "Password1")
    new_user=$(param new_user "alice")
    ldaps=$(param ldaps "false")
    subject_name=$new_user; [ -n "$domain" ] && subject_name="$new_user@$domain"

    pool=$(xe pool-list --minimal)
    master=$(xe pool-param-get uuid=$pool param-name=master)
    auth_type=$(xe host-param-get uuid=$master param-name=external-auth-type)
    auth_service=$(xe host-param-get uuid=$master param-name=external-auth-service-name)
    if [ -n "$domain" ] && [ "$auth_type" = "AD" ] \
        && [ "${auth_service,,}" = "${domain,,}" ]; then
        already_joined=true
        echo "Already joined to domain: $domain"
    else
        xe pool-enable-external-auth uuid=$pool auth-type=AD service-name="$domain" \
            config:user="$admin_user" config:pass="$admin_password" config:ldaps=$ldaps
        echo "Joined domain: ${domain:-(none given)}"
    fi
    subj=$(xe subject-add subject-name="$subject_name")
    xe subject-role-add uuid=$subj role-name=pool-admin
    name=$(xe subject-param-get uuid=$subj param-name=other-config param-key=subject-displayname)
    echo "Added subject $name with role pool-admin"

    # Revoking access does not end sessions the user already has: logging the subject out is a
    # separate act, and the one that actually gets them off the pool now rather than at next login.
    sid=$(xe subject-param-get uuid=$subj param-name=subject-identifier)
    xe session-subject-identifier-logout subject-identifier=$sid
    echo "  logged out $name"

    xe subject-remove subject-uuid=$subj
    if [ "$already_joined" = false ]; then
        # Leave the way it was found. Passing the admin credentials also removes the pool's computer
        # accounts from the directory; without them they stay behind in AD.
        xe pool-disable-external-auth uuid=$pool config:user="$admin_user" config:pass="$admin_password"
    fi
    echo "OK: manage-ad-users"
}
```

<details><summary>Sample output</summary>

```text
Joined domain: (none given)
Added subject Alice Admin with role pool-admin
  logged out Alice Admin
OK: manage-ad-users
```

</details>
