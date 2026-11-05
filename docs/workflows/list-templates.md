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
        // A snapshot is a template too (is_a_template is set on every snapshot), so leave those out.
        .Where(v => v.is_a_template && !v.is_a_snapshot).OrderBy(v => v.name_label).ToList();
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

<details><summary>Example output</summary>

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
    # A snapshot is a template too (is_a_template is set on every snapshot), so leave those out.
    templates = sorted((v for v in session.xenapi.VM.get_all_records().values()
                        if v["is_a_template"] and not v["is_a_snapshot"]),
                       key=lambda v: v["name_label"])
    print("Templates (%d):" % len(templates))
    for t in templates[:8]:
        is_default = "default_template" in t["other_config"]
        print("  - %s%s" % (t["name_label"], " [built-in]" if is_default else ""))
    print("OK: list-templates")
    session.xenapi.session.logout()
```

<details><summary>Example output</summary>

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
            // A snapshot is a template too (is_a_template is set on every snapshot), so leave those out.
            if (v.isATemplate && !v.isASnapshot) templates.add(v);
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

<details><summary>Example output</summary>

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
	"sort"

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
	// A snapshot is a template too (is_a_template is set on every snapshot), so leave those out.
	var templates []xenapi.VMRecord
	for _, v := range vms {
		if v.IsATemplate && !v.IsASnapshot {
			templates = append(templates, v)
		}
	}
	sort.Slice(templates, func(i, j int) bool { return templates[i].NameLabel < templates[j].NameLabel })
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

<details><summary>Example output</summary>

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
    # A snapshot is a template too (is_a_template is set on every snapshot), so leave those out.
    $templates = Get-XenVM | Where-Object { $_.is_a_template -and -not $_.is_a_snapshot } | Sort-Object name_label
    Write-Host "Templates ($(@($templates).Count)):"
    $templates | Select-Object -First 8 | ForEach-Object {
        $suffix = if ($_.other_config.ContainsKey("default_template")) { " [built-in]" } else { "" }
        Write-Host "  - $($_.name_label)$suffix"
    }
    Write-Host "OK: list-templates"
    $session | Disconnect-XenServer
}
```

<details><summary>Example output</summary>

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
    local t name
    # template-list leaves out snapshots, which are templates too. A built-in template carries
    # other-config:default_template.
    echo "Templates ($(count_csv "$(xe template-list --minimal)")):"
    for t in $(each_csv "$(xe template-list --minimal)"); do
        name=$(xe template-param-get uuid=$t param-name=name-label)
        if xe template-param-get uuid=$t param-name=other-config param-key=default_template >/dev/null 2>&1; then
            printf '%s\t  - %s [built-in]\n' "$name" "$name"
        else
            printf '%s\t  - %s\n' "$name" "$name"
        fi
    done | sort | head -8 | cut -f2-
    echo "OK: list-templates"
}
```

<details><summary>Example output</summary>

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
