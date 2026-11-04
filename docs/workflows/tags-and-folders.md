<!-- Generated from workflows.json, the example sources and a run of each example. Edit those, not this file. -->

# Tag and organize objects

Organize a pool with tags and folders: add tags to a VM and a host (tags work on any object type), place the VM in a folder, read it all back, then tidy up.

Workflow `tags-and-folders`. [All workflows](README.md) · [Connecting](connecting.md)

## C# (.NET)

Source: [`csharp/Organization/TagsAndFolders.cs`](../../csharp/Organization/TagsAndFolders.cs)

```csharp
/// <summary>
/// Organize a pool with tags and folders: add tags to a VM and a host (tags work on any object type),
/// place the VM in a folder, read it all back, then tidy up.
/// </summary>
/// <example>
/// <code>
/// Workflows.TagsAndFolders("https://xenserver", "root", password, "web-01");
/// </code>
/// </example>
public static void TagsAndFolders(string url, string user, string password, string vmName)
{
    var session = Connect(url, user, password);
    var vm = VmByName(session, vmName);
    var host = Host.get_all(session)[0].opaque_ref;

    // Tags work on any object type (VM, host, SR, network, …).
    VM.add_tags(session, vm, "web");
    Host.add_tags(session, host, "gold");
    Console.WriteLine($"VM tags:   {string.Join(", ", VM.get_tags(session, vm))}");
    Console.WriteLine($"Host tags: {string.Join(", ", Host.get_tags(session, host))}");

    // Folder placement lives in other_config["folder"] as a leading-slash path.
    VM.add_to_other_config(session, vm, "folder", "/Production/Web");
    Console.WriteLine($"VM folder: {VM.get_other_config(session, vm)["folder"]}");

    VM.remove_tags(session, vm, "web");
    Host.remove_tags(session, host, "gold");
    VM.remove_from_other_config(session, vm, "folder");
    Console.WriteLine("OK: tags-and-folders");
    session.logout();
}
```

<details><summary>Sample output</summary>

```text
VM tags:   web
Host tags: gold
VM folder: /Production/Web
OK: tags-and-folders
```

</details>

## Python

Source: [`python/organization/tags_and_folders.py`](../../python/organization/tags_and_folders.py)

```python
"""Tag and organize objects.

Organize a pool with tags and folders: add tags to a VM and a host (tags work on any object type),
place the VM in a folder, read it all back, then tidy up.

Run it::

    tags_and_folders("https://xenserver", "root", password, "web-01")
"""

from connection import connect
from helpers import vm_by_name


def tags_and_folders(url, username, password, vm_name):
    """Tag a VM and a host, and place the VM in a folder — the data behind Objects-by-Tag/Folder."""
    session = connect(url, username, password)
    vm = vm_by_name(session, vm_name)
    host = session.xenapi.host.get_all()[0]

    # Tags work on any object type (VM, host, SR, network, …).
    session.xenapi.VM.add_tags(vm, "web")
    session.xenapi.host.add_tags(host, "gold")
    print("VM tags:   %s" % session.xenapi.VM.get_tags(vm))
    print("Host tags: %s" % session.xenapi.host.get_tags(host))

    # Folder placement lives in other_config["folder"] as a leading-slash path.
    session.xenapi.VM.add_to_other_config(vm, "folder", "/Production/Web")
    print("VM folder: %s" % session.xenapi.VM.get_other_config(vm).get("folder"))

    # Tidy up.
    session.xenapi.VM.remove_tags(vm, "web")
    session.xenapi.host.remove_tags(host, "gold")
    session.xenapi.VM.remove_from_other_config(vm, "folder")
    print("OK: tags-and-folders")
    session.xenapi.session.logout()
```

<details><summary>Sample output</summary>

```text
VM tags:   ['web']
Host tags: ['gold']
VM folder: /Production/Web
OK: tags-and-folders
```

</details>

## Java

Source: [`java/src/main/java/com/xenserver/samples/organization/TagsAndFolders.java`](../../java/src/main/java/com/xenserver/samples/organization/TagsAndFolders.java)

```java
package com.xenserver.samples.organization;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.Host;
import com.xensource.xenapi.Session;
import com.xensource.xenapi.VM;

import static com.xenserver.samples.Helpers.vmByName;
import static com.xenserver.samples.PoolConnection.connect;

public final class TagsAndFolders {
    private TagsAndFolders() {
    }

    /**
     * Tag and organize objects.
     *
     * <p>Organize a pool with tags and folders: add tags to a VM and a host (tags work on any object
     * type), place the VM in a folder, read it all back, then tidy up.
     *
     * <p>Run it:
     *
     * <pre>{@code
     * TagsAndFolders.run("https://xenserver", "root", password, "web-01");
     * }</pre>
     */
    public static void run(String url, String user, String password, String vmName) throws Exception {
        Connection conn = connect(url, user, password);
        VM vm = vmByName(conn, vmName);
        Host host = Host.getAll(conn).iterator().next();

        // Tags work on any object type (VM, host, SR, network, …).
        vm.addTags(conn, "web");
        host.addTags(conn, "gold");
        System.out.println("VM tags:   " + vm.getTags(conn));
        System.out.println("Host tags: " + host.getTags(conn));

        // Folder placement lives in other_config["folder"] as a leading-slash path.
        vm.addToOtherConfig(conn, "folder", "/Production/Web");
        System.out.println("VM folder: " + vm.getOtherConfig(conn).get("folder"));

        vm.removeTags(conn, "web");
        host.removeTags(conn, "gold");
        vm.removeFromOtherConfig(conn, "folder");
        System.out.println("OK: tags-and-folders");
        Session.logout(conn);
    }
}
```

<details><summary>Sample output</summary>

```text
VM tags:   [web]
Host tags: [gold]
VM folder: /Production/Web
OK: tags-and-folders
```

</details>

## Go

Source: [`go/tags_and_folders.go`](../../go/tags_and_folders.go)

```go
package main

import (
	"fmt"

	"go/xenapi"
)

// tagsAndFolders - Tag and organize objects.
//
// Organize a pool with tags and folders: add tags to a VM and a host (tags work on any object
// type), place the VM in a folder, read it all back, then tidy up.
//
// Run it:
//
//	tagsAndFolders("https://xenserver", "root", password, "web-01")
func tagsAndFolders(url, user, password, vmName string) {
	session := connect(url, user, password)
	vm := vmByName(session, vmName)
	hosts, err := xenapi.Host.GetAll(session)
	check(err)
	host := hosts[0]

	// Tags work on any object type (VM, host, SR, network, …).
	check(xenapi.VM.AddTags(session, vm, "web"))
	check(xenapi.Host.AddTags(session, host, "gold"))
	vmTags, _ := xenapi.VM.GetTags(session, vm)
	hostTags, _ := xenapi.Host.GetTags(session, host)
	fmt.Printf("VM tags:   %v\n", vmTags)
	fmt.Printf("Host tags: %v\n", hostTags)

	// Folder placement lives in other_config["folder"] as a leading-slash path.
	check(xenapi.VM.AddToOtherConfig(session, vm, "folder", "/Production/Web"))
	oc, _ := xenapi.VM.GetOtherConfig(session, vm)
	fmt.Printf("VM folder: %s\n", oc["folder"])

	check(xenapi.VM.RemoveTags(session, vm, "web"))
	check(xenapi.Host.RemoveTags(session, host, "gold"))
	check(xenapi.VM.RemoveFromOtherConfig(session, vm, "folder"))
	fmt.Println("OK: tags-and-folders")
	session.Logout()
}
```

<details><summary>Sample output</summary>

```text
VM tags:   [web]
Host tags: [gold]
VM folder: /Production/Web
OK: tags-and-folders
```

</details>

## PowerShell

Source: [`powershell/Organization/Invoke-TagsAndFolders.ps1`](../../powershell/Organization/Invoke-TagsAndFolders.ps1)

```powershell
function Invoke-TagsAndFolders {
    <#
    .SYNOPSIS
        Tag and organize objects.
    .DESCRIPTION
        Organize a pool with tags and folders: add tags to a VM and a host (tags work on any object type),
        place the VM in a folder, read it all back, then tidy up.
    .EXAMPLE
        Invoke-TagsAndFolders -Url https://xenserver -UserName root -Password $password -VmName 'web-01'
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password,
        [Parameter(Mandatory = $true)][string]$VmName
    )
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password
    $vm = Get-XenVM -Name $VmName |
        Where-Object { -not $_.is_a_template -and -not $_.is_control_domain } | Select-Object -First 1
    if (-not $vm) { throw "No VM named '$VmName' was found." }
    $vmHost = Get-XenHost | Select-Object -First 1

    # Tags work on any object type (VM, host, SR, network, …): Add-Xen* appends a tag, the matching
    # Remove-Xen*Property drops it.
    $vm | Add-XenVM -Tags "web"
    $vmHost | Add-XenHost -Tags "gold"
    Write-Host "VM tags:   $((Get-XenVM -Ref $vm.opaque_ref).tags -join ', ')"
    Write-Host "Host tags: $((Get-XenHost -Ref $vmHost.opaque_ref).tags -join ', ')"

    # Folder placement lives in other_config["folder"] as a leading-slash path; merge it into the map.
    $current = $vm.other_config
    $oc = @{}
    foreach ($k in $current.Keys) { $oc[$k] = $current[$k] }
    $oc["folder"] = "/Production/Web"
    $vm | Set-XenVM -OtherConfig $oc
    Write-Host "VM folder: $((Get-XenVM -Ref $vm.opaque_ref).other_config['folder'])"

    # Tidy up.
    $vm | Remove-XenVMProperty -Tags "web"
    $vmHost | Remove-XenHostProperty -Tags "gold"
    $vm | Remove-XenVMProperty -OtherConfig "folder"
    Write-Host "OK: tags-and-folders"
    $session | Disconnect-XenServer
}
```

<details><summary>Sample output</summary>

```text
VM tags:   web
Host tags: gold
VM folder: /Production/Web
OK: tags-and-folders
```

</details>

## xe CLI

Source: [`cli/organization/tags-and-folders.sh`](../../cli/organization/tags-and-folders.sh)

```bash
# Tag and organize objects.
#
# Organize a pool with tags and folders: add tags to a VM and a host (tags work on any object type), place the
# VM in a folder, read it all back, then tidy up.
#
# Run it:
#   ./workflows.sh tags-and-folders https://xenserver root "$password"

tags_and_folders() {
    vm=$(vm_uuid web-01); h=$(first_host)
    xe vm-param-add uuid=$vm param-name=tags param-key=web
    xe host-param-add uuid=$h param-name=tags param-key=gold
    echo "VM tags:   $(xe vm-param-get uuid=$vm param-name=tags)"
    echo "Host tags: $(xe host-param-get uuid=$h param-name=tags)"
    xe vm-param-set uuid=$vm other-config:folder=/Production/Web
    echo "VM folder: $(xe vm-param-get uuid=$vm param-name=other-config param-key=folder)"
    xe vm-param-remove uuid=$vm param-name=tags param-key=web
    xe host-param-remove uuid=$h param-name=tags param-key=gold
    xe vm-param-remove uuid=$vm param-name=other-config param-key=folder
    echo "OK: tags-and-folders"
}
```

<details><summary>Sample output</summary>

```text
VM tags:   web
Host tags: gold
VM folder: /Production/Web
OK: tags-and-folders
```

</details>
