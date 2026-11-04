<!-- Generated from workflows.json, the example sources and a run of each example. Edit those, not this file. -->

# Custom fields

Attach and read custom name/value fields on a VM — arbitrary metadata you define, stored on the object.

Workflow `custom-fields`. [All workflows](README.md) · [Connecting](connecting.md)

## C# (.NET)

Source: [`csharp/Organization/CustomFields.cs`](../../csharp/Organization/CustomFields.cs)

```csharp
/// <summary>
/// Attach and read custom name/value fields on a VM — arbitrary metadata you define, stored on the
/// object.
/// </summary>
/// <example>
/// <code>
/// Workflows.CustomFields("https://xenserver", "root", password, "web-01");
/// </code>
/// </example>
public static void CustomFields(string url, string user, string password, string vmName)
{
    var session = Connect(url, user, password);
    // XenCenter's custom fields are stored in other_config under "XenCenter.CustomFields.<name>".
    var vm = VmByName(session, vmName);
    const string key = "XenCenter.CustomFields.Owner";
    VM.add_to_other_config(session, vm, key, "Platform Team");
    Console.WriteLine($"Custom field Owner = {VM.get_other_config(session, vm)[key]}");

    VM.remove_from_other_config(session, vm, key);
    Console.WriteLine("OK: custom-fields");
    session.logout();
}
```

<details><summary>Sample output</summary>

```text
Custom field Owner = Platform Team
OK: custom-fields
```

</details>

## Python

Source: [`python/organization/custom_fields.py`](../../python/organization/custom_fields.py)

```python
"""Custom fields.

Attach and read custom name/value fields on a VM — arbitrary metadata you define, stored on the
object.

Run it::

    custom_fields("https://xenserver", "root", password, "web-01")
"""

from connection import connect
from helpers import vm_by_name


def custom_fields(url, username, password, vm_name):
    """XenCenter's custom fields are stored in other_config under "XenCenter.CustomFields.<name>"."""
    session = connect(url, username, password)
    vm = vm_by_name(session, vm_name)
    key = "XenCenter.CustomFields.Owner"
    session.xenapi.VM.add_to_other_config(vm, key, "Platform Team")
    print("Custom field Owner = %s" % session.xenapi.VM.get_other_config(vm)[key])

    session.xenapi.VM.remove_from_other_config(vm, key)
    print("OK: custom-fields")
    session.xenapi.session.logout()
```

<details><summary>Sample output</summary>

```text
Custom field Owner = Platform Team
OK: custom-fields
```

</details>

## Java

Source: [`java/src/main/java/com/xenserver/samples/organization/CustomFields.java`](../../java/src/main/java/com/xenserver/samples/organization/CustomFields.java)

```java
package com.xenserver.samples.organization;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.Session;
import com.xensource.xenapi.VM;

import static com.xenserver.samples.Helpers.vmByName;
import static com.xenserver.samples.PoolConnection.connect;

public final class CustomFields {
    private CustomFields() {
    }

    /**
     * Custom fields.
     *
     * <p>Attach and read custom name/value fields on a VM — arbitrary metadata you define, stored on the
     * object.
     *
     * <p>Run it:
     *
     * <pre>{@code
     * CustomFields.run("https://xenserver", "root", password, "web-01");
     * }</pre>
     */
    public static void run(String url, String user, String password, String vmName) throws Exception {
        Connection conn = connect(url, user, password);
        // XenCenter's custom fields are stored in other_config under "XenCenter.CustomFields.<name>".
        VM vm = vmByName(conn, vmName);
        final String key = "XenCenter.CustomFields.Owner";
        vm.addToOtherConfig(conn, key, "Platform Team");
        System.out.println("Custom field Owner = " + vm.getOtherConfig(conn).get(key));

        vm.removeFromOtherConfig(conn, key);
        System.out.println("OK: custom-fields");
        Session.logout(conn);
    }
}
```

<details><summary>Sample output</summary>

```text
Custom field Owner = Platform Team
OK: custom-fields
```

</details>

## Go

Source: [`go/custom_fields.go`](../../go/custom_fields.go)

```go
package main

import (
	"fmt"

	"go/xenapi"
)

// customFields - Custom fields.
//
// Attach and read custom name/value fields on a VM — arbitrary metadata you define, stored on the
// object.
//
// Run it:
//
//	customFields("https://xenserver", "root", password, "web-01")
func customFields(url, user, password, vmName string) {
	session := connect(url, user, password)
	// XenCenter's custom fields are stored in other_config under "XenCenter.CustomFields.<name>".
	vm := vmByName(session, vmName)
	const key = "XenCenter.CustomFields.Owner"
	check(xenapi.VM.AddToOtherConfig(session, vm, key, "Platform Team"))
	oc, _ := xenapi.VM.GetOtherConfig(session, vm)
	fmt.Printf("Custom field Owner = %s\n", oc[key])

	check(xenapi.VM.RemoveFromOtherConfig(session, vm, key))
	fmt.Println("OK: custom-fields")
	session.Logout()
}
```

<details><summary>Sample output</summary>

```text
Custom field Owner = Platform Team
OK: custom-fields
```

</details>

## PowerShell

Source: [`powershell/Organization/Invoke-CustomFields.ps1`](../../powershell/Organization/Invoke-CustomFields.ps1)

```powershell
function Invoke-CustomFields {
    <#
    .SYNOPSIS
        Custom fields.
    .DESCRIPTION
        Attach and read custom name/value fields on a VM — arbitrary metadata you define, stored on the
        object.
    .EXAMPLE
        Invoke-CustomFields -Url https://xenserver -UserName root -Password $password -VmName 'web-01'
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password,
        [Parameter(Mandatory = $true)][string]$VmName
    )
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password
    # XenCenter's custom fields are stored in other_config under "XenCenter.CustomFields.<name>".
    # Set-XenVM -OtherConfig replaces the whole map, so merge the field into a copy; Remove-XenVMProperty
    # -OtherConfig then drops it again by key.
    $vm = Get-XenVM -Name $VmName |
        Where-Object { -not $_.is_a_template -and -not $_.is_control_domain } | Select-Object -First 1
    if (-not $vm) { throw "No VM named '$VmName' was found." }
    $key = "XenCenter.CustomFields.Owner"

    $current = $vm.other_config
    $oc = @{}
    foreach ($k in $current.Keys) { $oc[$k] = $current[$k] }
    $oc[$key] = "Platform Team"
    $vm | Set-XenVM -OtherConfig $oc
    Write-Host "Custom field Owner = $((Get-XenVM -Ref $vm.opaque_ref).other_config[$key])"

    $vm | Remove-XenVMProperty -OtherConfig $key
    Write-Host "OK: custom-fields"
    $session | Disconnect-XenServer
}
```

<details><summary>Sample output</summary>

```text
Custom field Owner = Platform Team
OK: custom-fields
```

</details>

## xe CLI

Source: [`cli/organization/custom-fields.sh`](../../cli/organization/custom-fields.sh)

```bash
# Custom fields.
#
# Attach and read custom name/value fields on a VM — arbitrary metadata you define, stored on the object.
#
# Run it:
#   ./workflows.sh custom-fields https://xenserver root "$password"

custom_fields() {
    vm=$(vm_uuid web-01)
    xe vm-param-set uuid=$vm other-config:XenCenter.CustomFields.Owner="Platform Team"
    echo "Owner = $(xe vm-param-get uuid=$vm param-name=other-config param-key=XenCenter.CustomFields.Owner)"
    xe vm-param-remove uuid=$vm param-name=other-config param-key=XenCenter.CustomFields.Owner
    echo "OK: custom-fields"
}
```

<details><summary>Sample output</summary>

```text
Owner = Platform Team
OK: custom-fields
```

</details>
