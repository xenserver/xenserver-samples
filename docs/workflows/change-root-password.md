<!-- Generated from workflows.json, the example sources and a run of each example. Edit those, not this file. -->

# Change the root password

Change the local superuser password, handle the wrong-old-password failure, and change it back.

**Caution:** changes the root password; a failure part way can lock you out of the host.

Workflow `change-root-password`. [All workflows](README.md) · [Connecting](connecting.md)

## C# (.NET)

Source: [`csharp/HostsAndPools/ChangeRootPassword.cs`](../../csharp/HostsAndPools/ChangeRootPassword.cs)

```csharp
/// <summary>
/// Change the local superuser password, handle the wrong-old-password failure, and change it back.
/// </summary>
/// <example>
/// <code>
/// Workflows.ChangeRootPassword("https://xenserver", "root", password);
/// </code>
/// </example>
public static void ChangeRootPassword(string url, string user, string password)
{
    var session = Connect(url, user, password);
    const string temporary = "sdk-example-temp-password";

    // session.change_password takes the OLD password as well as the new one, even though you are
    // already authenticated.
    Session.change_password(session, password, temporary);
    Console.WriteLine("Password changed.");

    // The existing session stays valid afterwards — only NEW connections need the new password, so a
    // script can carry on without reconnecting.
    Console.WriteLine($"Session still usable: {Pool.get_all(session).Count == 1}");

    // session.change_password on a ROOT session ignores the old password entirely (CA-13567): the
    // call succeeds regardless of what old_pwd is, so "supplying the wrong old password" is not a
    // real failure to demonstrate here. The real gate is who may call this at all.
    Console.WriteLine($"Is local superuser (may call change_password): {session.IsLocalSuperuser}");

    Session.change_password(session, temporary, password);
    Console.WriteLine("Password restored.");
    Console.WriteLine("OK: change-root-password");
    session.logout();
}
```

<details><summary>Sample output</summary>

```text
Password changed.
Session still usable: True
Is local superuser (may call change_password): True
Password restored.
OK: change-root-password
```

</details>

## Python

Source: [`python/hosts_and_pools/change_root_password.py`](../../python/hosts_and_pools/change_root_password.py)

```python
"""Change the root password.

Change the local superuser password, handle the wrong-old-password failure, and change it back.

Run it::

    change_root_password("https://xenserver", "root", password)
"""

from connection import connect


def change_root_password(url, username, password):
    """Change the local superuser password, then change it back."""
    session = connect(url, username, password)
    temporary = "sdk-example-temp-password"

    # change_password takes the OLD password as well as the new one, even though you are already
    # authenticated.
    session.xenapi.session.change_password(password, temporary)
    print("Password changed.")

    # The existing session stays valid afterwards - only NEW connections need the new password.
    print("Session still usable: %s" % (len(session.xenapi.pool.get_all()) == 1))

    # change_password on a ROOT session ignores the old password entirely (CA-13567): the call
    # succeeds whatever old_pwd is, so a wrong old password is not a failure to demonstrate here. The
    # real gate is who may call this at all: only a local superuser session.
    print("Is local superuser (may call change_password): %s"
          % session.xenapi.session.get_is_local_superuser(session._session))

    session.xenapi.session.change_password(temporary, password)
    print("Password restored.")
    print("OK: change-root-password")
    session.xenapi.session.logout()
```

<details><summary>Sample output</summary>

```text
Password changed.
Session still usable: True
Is local superuser (may call change_password): True
Password restored.
OK: change-root-password
```

</details>

## Java

Source: [`java/src/main/java/com/xenserver/samples/hostsandpools/ChangeRootPassword.java`](../../java/src/main/java/com/xenserver/samples/hostsandpools/ChangeRootPassword.java)

```java
package com.xenserver.samples.hostsandpools;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.Pool;
import com.xensource.xenapi.Session;

import static com.xenserver.samples.PoolConnection.connect;

public final class ChangeRootPassword {
    private ChangeRootPassword() {
    }

    /**
     * Change the root password.
     *
     * <p>Change the local superuser password, handle the wrong-old-password failure, and change it back.
     */
    public static void run(String url, String user, String password) throws Exception {
        Connection conn = connect(url, user, password);
        final String temporary = "sdk-example-temp-password";

        // changePassword takes the OLD password as well as the new one, even though you are already
        // authenticated.
        Session.changePassword(conn, password, temporary);
        System.out.println("Password changed.");

        // The existing session stays valid afterwards - only NEW connections need the new password.
        System.out.println("Session still usable: " + (Pool.getAll(conn).size() == 1));

        // Not demonstrated: a "wrong old password is rejected" check. session.change_password on a
        // ROOT session ignores old_pwd entirely (CA-13567, confirmed in xapi_session.ml) - the call
        // succeeds regardless of what's passed as the old password. The real gate is that only a
        // session with is_local_superuser may call this at all.

        Session.changePassword(conn, temporary, password);
        System.out.println("Password restored.");
        System.out.println("OK: change-root-password");
        Session.logout(conn);
    }
}
```

<details><summary>Sample output</summary>

```text
Password changed.
Session still usable: true
Password restored.
OK: change-root-password
```

</details>

## Go

Source: [`go/change_root_password.go`](../../go/change_root_password.go)

```go
package main

import (
	"fmt"

	"go/xenapi"
)

// changeRootPassword - Change the root password.
//
// Change the local superuser password, handle the wrong-old-password failure, and change it back.
func changeRootPassword(url, user, password string) {
	session := connect(url, user, password)
	const temporary = "sdk-example-temp-password"

	// ChangePassword takes the OLD password as well as the new one, even though you are already
	// authenticated.
	check(session.ChangePassword(password, temporary))
	fmt.Println("Password changed.")
	// Whatever happens next, put the password back: a failure part-way would otherwise leave root on
	// the temporary one.
	restored := false
	defer func() {
		if !restored {
			session.ChangePassword(temporary, password)
		}
	}()

	// The existing session stays valid afterwards - only NEW connections need the new password.
	pools, err := xenapi.Pool.GetAll(session)
	check(err)
	fmt.Printf("Session still usable: %t\n", len(pools) == 1)

	// session.change_password on a ROOT session ignores old_pwd entirely (CA-13567, confirmed in
	// xapi_session.ml) - any string would also be accepted, so there is no "wrong old password is
	// rejected" failure to demonstrate here. The real gate is upstream of that: only a session
	// authenticated as the local superuser may call this at all. The Go binding keeps its session
	// id private, so check that the same way the RRD/export examples obtain one of their own - with
	// the NEW password, which is the one any new connection needs now.
	sid := rawLogin(url, user, temporary)
	isSuperuser := rawRPC(url, "session.get_is_local_superuser", sid, sid)
	fmt.Printf("Allowed because session.is_local_superuser = %s\n", isSuperuser)
	rawRPC(url, "session.logout", sid)

	check(session.ChangePassword(temporary, password))
	restored = true
	fmt.Println("Password restored.")
	fmt.Println("OK: change-root-password")
	session.Logout()
}
```

<details><summary>Sample output</summary>

```text
Password changed.
Session still usable: true
Allowed because session.is_local_superuser = true
Password restored.
OK: change-root-password
```

</details>

## PowerShell

Source: [`powershell/HostsAndPools/Invoke-ChangeRootPassword.ps1`](../../powershell/HostsAndPools/Invoke-ChangeRootPassword.ps1)

```powershell
function Invoke-ChangeRootPassword {
    <#
    .SYNOPSIS
        Change the root password.
    .DESCRIPTION
        Change the local superuser password, handle the wrong-old-password failure, and change it back.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password
    )
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password
    $temporary = 'sdk-example-temp-password'

    # The module ships no cmdlet for session.change_password, so this is the one place these examples
    # call the binding directly. The session Connect-XenServer hands back IS a XenAPI.Session, which is
    # exactly what the static wants. Note it takes the OLD password as well as the new one, even though
    # you are already authenticated.
    [XenAPI.Session]::change_password($session, $Password, $temporary)
    Write-Host "Password changed."

    # The existing session stays valid afterwards - only NEW connections need the new password, so a
    # script can carry on without reconnecting.
    Write-Host "Session still usable: $(@(Get-XenPool).Count -eq 1)"

    # change_password on a ROOT session ignores the old password entirely (CA-13567, confirmed in
    # xapi_session.ml) - the call succeeds regardless of what is passed as the old password, so there is
    # no "wrong old password is rejected" demonstration to show here. The real gate is who may call this
    # at all: only a session with is_local_superuser may.
    Write-Host "is_local_superuser: $($session.IsLocalSuperuser)"

    [XenAPI.Session]::change_password($session, $temporary, $Password)
    Write-Host "Password restored."
    Write-Host "OK: change-root-password"
    Disconnect-XenServer -Session $session
}
```

<details><summary>Sample output</summary>

```text
Password changed.
Session still usable: True
is_local_superuser: True
Password restored.
OK: change-root-password
```

</details>

## xe CLI

Source: [`cli/hosts-and-pools/change-root-password.sh`](../../cli/hosts-and-pools/change-root-password.sh)

```bash
# Change the root password.
#
# Change the local superuser password, handle the wrong-old-password failure, and change it back.
#
# Run it:
#   ./workflows.sh change-root-password https://xenserver root "$password"

change_root_password() {
    # xe exposes this as user-password-change. It takes the OLD password as well as the new one, even
    # though you are already authenticated - but a root session's old_pwd is never actually checked
    # (CA-13567): the only real gate is that the SESSION itself has to be a local superuser's, which this
    # one necessarily is. There is no "wrong old password is rejected" demonstration worth making here.
    original=$pass temporary=xe-example-temp-password
    xe user-password-change old="$original" new=$temporary
    echo "Password changed."
    # Unlike an SDK session, xe has no session to keep: every command logs in afresh, so from here on
    # it needs the NEW password - including the command that changes it back. And restore it however the
    # script ends (set -e exits on the first failure), or root would be left on the temporary password.
    pass=$temporary
    trap 'pass=$temporary; xe user-password-change old=$temporary new="$original" >/dev/null 2>&1' EXIT

    echo "New logins work with the new password: $(count_csv "$(xe pool-list --minimal)") pool"

    xe user-password-change old=$temporary new="$original"
    pass=$original
    trap - EXIT
    echo "Password restored."
    echo "OK: change-root-password"
}
```

<details><summary>Sample output</summary>

```text
Password changed.
New logins work with the new password: 1 pool
Password restored.
OK: change-root-password
```

</details>
