<!-- Generated from workflows.json, the example sources and a run of each example. Edit those, not this file. -->

# List RBAC roles

Enumerate the pool's role-based access control (RBAC) roles — the roles that can be granted to users.

Workflow `list-roles`. [All workflows](README.md) · [Connecting](connecting.md)

## C# (.NET)

Source: [`csharp/SecurityAndAccess/ListRoles.cs`](../../csharp/SecurityAndAccess/ListRoles.cs)

```csharp
/// <summary>
/// Enumerate the pool's role-based access control (RBAC) roles — the roles that can be granted to users.
/// </summary>
/// <example>
/// <code>
/// Workflows.ListRoles("https://xenserver", "root", password);
/// </code>
/// </example>
public static void ListRoles(string url, string user, string password)
{
    var session = Connect(url, user, password);
    // RBAC subjects map to these roles. Role records include every permission too; the roles a user
    // can be granted are the ones made of permissions (non-empty subroles), as xe role-list shows.
    var roles = Role.get_all_records(session).Values.Where(r => r.subroles.Count > 0)
        .Select(r => r.name_label).Distinct().OrderBy(n => n).ToList();
    Console.WriteLine($"Roles ({roles.Count}): {string.Join(", ", roles.Take(8))}");
    Console.WriteLine("OK: list-roles");
    session.logout();
}
```

<details><summary>Example output</summary>

```text
Roles (7): client-cert, pool-admin, pool-operator, read-only, vm-admin, vm-operator, vm-power-admin
OK: list-roles
```

</details>

## Python

Source: [`python/security_and_access/list_roles.py`](../../python/security_and_access/list_roles.py)

```python
"""List RBAC roles.

Enumerate the pool's role-based access control (RBAC) roles — the roles that can be granted to
users.

Run it::

    list_roles("https://xenserver", "root", password)
"""

from connection import connect


def list_roles(url, username, password):
    """List the RBAC roles."""
    session = connect(url, username, password)
    # Note the class is lowercase 'role' in the binding. Role records include every permission too; the
    # roles a user can be granted are the ones made of permissions (non-empty subroles), as xe role-list shows.
    roles = sorted({r["name_label"] for r in session.xenapi.role.get_all_records().values() if r["subroles"]})
    print("Roles (%d): %s" % (len(roles), ", ".join(roles[:8])))
    print("OK: list-roles")
    session.xenapi.session.logout()
```

<details><summary>Example output</summary>

```text
Roles (7): client-cert, pool-admin, pool-operator, read-only, vm-admin, vm-operator, vm-power-admin
OK: list-roles
```

</details>

## Java

Source: [`java/src/main/java/com/xenserver/samples/securityandaccess/ListRoles.java`](../../java/src/main/java/com/xenserver/samples/securityandaccess/ListRoles.java)

```java
package com.xenserver.samples.securityandaccess;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.Role;
import com.xensource.xenapi.Session;

import java.util.Set;

import static com.xenserver.samples.PoolConnection.connect;

public final class ListRoles {
    private ListRoles() {
    }

    /**
     * List RBAC roles.
     *
     * <p>Enumerate the pool's role-based access control (RBAC) roles — the roles that can be granted to
     * users.
     *
     * <p>Run it:
     *
     * <pre>{@code
     * ListRoles.run("https://xenserver", "root", password);
     * }</pre>
     */
    public static void run(String url, String user, String password) throws Exception {
        Connection conn = connect(url, user, password);
        // RBAC subjects map to these roles. Role records include every permission too; the roles a user
        // can be granted are the ones made of permissions (non-empty subroles), as xe role-list shows.
        Set<String> roles = new java.util.TreeSet<>(); // distinct + sorted by name
        for (Role.Record r : Role.getAllRecords(conn).values()) if (!r.subroles.isEmpty()) roles.add(r.nameLabel);
        StringBuilder first = new StringBuilder();
        int shown = 0;
        for (String name : roles) {
            if (shown++ >= 8) break;
            if (first.length() > 0) first.append(", ");
            first.append(name);
        }
        System.out.println("Roles (" + roles.size() + "): " + first);
        System.out.println("OK: list-roles");
        Session.logout(conn);
    }
}
```

<details><summary>Example output</summary>

```text
Roles (7): client-cert, pool-admin, pool-operator, read-only, vm-admin, vm-operator, vm-power-admin
OK: list-roles
```

</details>

## Go

Source: [`go/list_roles.go`](../../go/list_roles.go)

```go
package main

import (
	"fmt"
	"strings"

	"go/xenapi"
)

// listRoles - List RBAC roles.
//
// Enumerate the pool's role-based access control (RBAC) roles — the roles that can be granted to
// users.
//
// Run it:
//
//	listRoles("https://xenserver", "root", password)
func listRoles(url, user, password string) {
	session := connect(url, user, password)
	// RBAC subjects map to these roles. Role records include every permission too; the roles a user
	// can be granted are the ones made of permissions (non-empty subroles), as xe role-list shows.
	roles, err := xenapi.Role.GetAllRecords(session)
	check(err)
	seen := map[string]bool{}
	var names []string
	for _, r := range roles {
		if len(r.Subroles) > 0 && !seen[r.NameLabel] {
			seen[r.NameLabel] = true
			names = append(names, r.NameLabel)
		}
	}
	shown := names
	if len(shown) > 8 {
		shown = shown[:8]
	}
	fmt.Printf("Roles (%d): %s\n", len(names), strings.Join(shown, ", "))
	fmt.Println("OK: list-roles")
	session.Logout()
}
```

<details><summary>Example output</summary>

```text
Roles (7): pool-operator, vm-operator, read-only, pool-admin, vm-power-admin, client-cert, vm-admin
OK: list-roles
```

</details>

## PowerShell

Source: [`powershell/SecurityAndAccess/Invoke-ListRoles.ps1`](../../powershell/SecurityAndAccess/Invoke-ListRoles.ps1)

```powershell
function Invoke-ListRoles {
    <#
    .SYNOPSIS
        List RBAC roles.
    .DESCRIPTION
        Enumerate the pool's role-based access control (RBAC) roles — the roles that can be granted to
        users.
    .EXAMPLE
        Invoke-ListRoles -Url https://xenserver -UserName root -Password $password
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password
    )
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password
    # RBAC subjects map to these roles. Role records include every permission too; the roles a user
    # can be granted are the ones made of permissions (non-empty subroles), as xe role-list shows.
    $roles = Get-XenRole | Where-Object { $_.subroles.Count -gt 0 } |
        Select-Object -ExpandProperty name_label -Unique | Sort-Object
    Write-Host "Roles ($(@($roles).Count)): $(($roles | Select-Object -First 8) -join ', ')"
    Write-Host "OK: list-roles"
    $session | Disconnect-XenServer
}
```

<details><summary>Example output</summary>

```text
Roles (7): client-cert, pool-admin, pool-operator, read-only, vm-admin, vm-operator, vm-power-admin
OK: list-roles
```

</details>

## xe CLI

Source: [`cli/security-and-access/list-roles.sh`](../../cli/security-and-access/list-roles.sh)

```bash
# List RBAC roles.
#
# Enumerate the pool's role-based access control (RBAC) roles — the roles that can be granted to users.
#
# Run it:
#   ./workflows.sh list-roles https://xenserver root "$password"

list_roles() {
    # role-list shows the roles a user can be granted, not the permissions they are made of. Its field
    # is `name`: a role has no name-label, and asking for one prints nothing.
    echo "Roles: $(xe role-list params=name --minimal)"
    echo "OK: list-roles"
}
```

<details><summary>Example output</summary>

```text
Roles: pool-admin,pool-operator,vm-power-admin,vm-admin,vm-operator,read-only,client-cert
OK: list-roles
```

</details>
