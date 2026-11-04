<!-- Generated from workflows.json, the example sources and a run of each example. Edit those, not this file. -->

# List templates

Enumerate the pool's VM templates, both built-in and custom.

Workflow `list-templates`. [All workflows](README.md) · [Connecting](connecting.md)

## C# (.NET)

Source: [`csharp/VirtualMachines/ListTemplates.cs`](../../csharp/VirtualMachines/ListTemplates.cs)

```csharp
/// <summary>
/// Enumerate the pool's VM templates, both built-in and custom.
/// </summary>
/// <example>
/// <code>
/// Workflows.ListTemplates("https://xenserver", "root", password);
/// </code>
/// </example>
public static void ListTemplates(string url, string user, string password)
{
    var session = Connect(url, user, password);
    var templates = VM.get_all_records(session).Values
        .Where(v => v.is_a_template).OrderBy(v => v.name_label).ToList();
    Console.WriteLine($"Templates ({templates.Count}):");
    foreach (var t in templates.Take(8))
    {
        var isDefault = t.other_config.ContainsKey("default_template");
        Console.WriteLine($"  - {t.name_label}{(isDefault ? " [built-in]" : "")}");
    }
    Console.WriteLine("OK: list-templates");
    session.logout();
}
```

<details><summary>Sample output</summary>

```text
Templates (27):
  - AlmaLinux 10 [built-in]
  - AlmaLinux 8 [built-in]
  - AlmaLinux 9 [built-in]
  - CentOS Stream 10 [built-in]
  - CentOS Stream 9 [built-in]
  - Debian Bookworm 12 [built-in]
  - Debian Bullseye 11 [built-in]
  - Gooroom Platform 2.0 [built-in]
OK: list-templates
```

</details>

## Python

Source: [`python/virtual_machines/list_templates.py`](../../python/virtual_machines/list_templates.py)

```python
"""List templates.

Enumerate the pool's VM templates, both built-in and custom.

Run it::

    list_templates("https://xenserver", "root", password)
"""

from connection import connect


def list_templates(url, username, password):
    """List the pool's templates, flagging the built-in (default) ones."""
    session = connect(url, username, password)
    templates = sorted((v for v in session.xenapi.VM.get_all_records().values() if v["is_a_template"]),
                       key=lambda v: v["name_label"])
    print("Templates (%d):" % len(templates))
    for t in templates[:8]:
        is_default = "default_template" in t["other_config"]
        print("  - %s%s" % (t["name_label"], " [built-in]" if is_default else ""))
    print("OK: list-templates")
    session.xenapi.session.logout()
```

<details><summary>Sample output</summary>

```text
Templates (27):
  - AlmaLinux 10 [built-in]
  - AlmaLinux 8 [built-in]
  - AlmaLinux 9 [built-in]
  - CentOS Stream 10 [built-in]
  - CentOS Stream 9 [built-in]
  - Debian Bookworm 12 [built-in]
  - Debian Bullseye 11 [built-in]
  - Gooroom Platform 2.0 [built-in]
OK: list-templates
```

</details>

## Java

Source: [`java/src/main/java/com/xenserver/samples/virtualmachines/ListTemplates.java`](../../java/src/main/java/com/xenserver/samples/virtualmachines/ListTemplates.java)

```java
package com.xenserver.samples.virtualmachines;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.Session;
import com.xensource.xenapi.VM;

import static com.xenserver.samples.PoolConnection.connect;

public final class ListTemplates {
    private ListTemplates() {
    }

    /**
     * List templates.
     *
     * <p>Enumerate the pool's VM templates, both built-in and custom.
     *
     * <p>Run it:
     *
     * <pre>{@code
     * ListTemplates.run("https://xenserver", "root", password);
     * }</pre>
     */
    public static void run(String url, String user, String password) throws Exception {
        Connection conn = connect(url, user, password);
        java.util.List<VM.Record> templates = new java.util.ArrayList<>();
        for (VM.Record v : VM.getAllRecords(conn).values())
            if (v.isATemplate) templates.add(v);
        templates.sort(java.util.Comparator.comparing((VM.Record r) -> r.nameLabel));
        System.out.println("Templates (" + templates.size() + "):");
        int shown = 0;
        for (VM.Record t : templates) {
            if (shown++ >= 8) break;
            boolean isDefault = t.otherConfig.containsKey("default_template");
            System.out.println("  - " + t.nameLabel + (isDefault ? " [built-in]" : ""));
        }
        System.out.println("OK: list-templates");
        Session.logout(conn);
    }
}
```

<details><summary>Sample output</summary>

```text
Templates (27):
  - AlmaLinux 10 [built-in]
  - AlmaLinux 8 [built-in]
  - AlmaLinux 9 [built-in]
  - CentOS Stream 10 [built-in]
  - CentOS Stream 9 [built-in]
  - Debian Bookworm 12 [built-in]
  - Debian Bullseye 11 [built-in]
  - Gooroom Platform 2.0 [built-in]
OK: list-templates
```

</details>

## Go

Source: [`go/list_templates.go`](../../go/list_templates.go)

```go
package main

import (
	"fmt"

	"go/xenapi"
)

// listTemplates - List templates.
//
// Enumerate the pool's VM templates, both built-in and custom.
//
// Run it:
//
//	listTemplates("https://xenserver", "root", password)
func listTemplates(url, user, password string) {
	session := connect(url, user, password)
	vms, err := xenapi.VM.GetAllRecords(session)
	check(err)
	var templates []xenapi.VMRecord
	for _, v := range vms {
		if v.IsATemplate {
			templates = append(templates, v)
		}
	}
	fmt.Printf("Templates (%d):\n", len(templates))
	for i, t := range templates {
		if i >= 8 {
			break
		}
		badge := ""
		if _, ok := t.OtherConfig["default_template"]; ok {
			badge = " [built-in]"
		}
		fmt.Printf("  - %s%s\n", t.NameLabel, badge)
	}
	fmt.Println("OK: list-templates")
	session.Logout()
}
```

<details><summary>Sample output</summary>

```text
Templates (27):
  - Gooroom Platform 2.0 [built-in]
  - Ubuntu Resolute Raccoon 26.04 [built-in]
  - Debian Bullseye 11 [built-in]
  - CentOS Stream 9 [built-in]
  - Other install media [built-in]
  - AlmaLinux 8 [built-in]
  - Windows Server 2016 (64-bit) [built-in]
  - Windows Server 2019 (64-bit) [built-in]
OK: list-templates
```

</details>

## PowerShell

Source: [`powershell/VirtualMachines/Invoke-ListTemplates.ps1`](../../powershell/VirtualMachines/Invoke-ListTemplates.ps1)

```powershell
function Invoke-ListTemplates {
    <#
    .SYNOPSIS
        List templates.
    .DESCRIPTION
        Enumerate the pool's VM templates, both built-in and custom.
    .EXAMPLE
        Invoke-ListTemplates -Url https://xenserver -UserName root -Password $password
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password
    )
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password
    $templates = Get-XenVM | Where-Object { $_.is_a_template } | Sort-Object name_label
    Write-Host "Templates ($(@($templates).Count)):"
    $templates | Select-Object -First 8 | ForEach-Object {
        $suffix = if ($_.other_config.ContainsKey("default_template")) { " [built-in]" } else { "" }
        Write-Host "  - $($_.name_label)$suffix"
    }
    Write-Host "OK: list-templates"
    $session | Disconnect-XenServer
}
```

<details><summary>Sample output</summary>

```text
Templates (27):
  - AlmaLinux 10 [built-in]
  - AlmaLinux 8 [built-in]
  - AlmaLinux 9 [built-in]
  - CentOS Stream 10 [built-in]
  - CentOS Stream 9 [built-in]
  - Debian Bookworm 12 [built-in]
  - Debian Bullseye 11 [built-in]
  - Gooroom Platform 2.0 [built-in]
OK: list-templates
```

</details>

## xe CLI

Source: [`cli/virtual-machines/list-templates.sh`](../../cli/virtual-machines/list-templates.sh)

```bash
# List templates.
#
# Enumerate the pool's VM templates, both built-in and custom.
#
# Run it:
#   ./workflows.sh list-templates https://xenserver root "$password"

list_templates() {
    echo "Templates ($(count_csv "$(xe template-list --minimal)")):"
    IFS=, read -ra names <<< "$(xe template-list params=name-label --minimal)"
    printf '%s\n' "${names[@]:0:8}"
    echo "OK: list-templates"
}
```

<details><summary>Sample output</summary>

```text
Templates (27):
AlmaLinux 10
AlmaLinux 8
AlmaLinux 9
CentOS Stream 10
CentOS Stream 9
Debian Bookworm 12
Debian Bullseye 11
Gooroom Platform 2.0
OK: list-templates
```

</details>
