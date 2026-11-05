<!-- Generated from workflows.json, the example sources and a run of each example. Edit those, not this file. -->

# VM boot configuration

Set a VM's vCPU counts and boot order, then read them back.

Workflow `vm-boot-config`. [All workflows](README.md) · [Connecting](connecting.md)

## C# (.NET)

Source: [`csharp/VirtualMachines/VmBootConfig.cs`](../../csharp/VirtualMachines/VmBootConfig.cs)

```csharp
/// <summary>
/// Set a VM's vCPU counts and boot order, then read them back.
/// </summary>
/// <example>
/// <code>
/// Workflows.VmBootConfig("https://xenserver", "root", password, "Rocky Linux 8");
/// </code>
/// </example>
public static void VmBootConfig(string url, string user, string password,
    string templateName, string newVmName = "sdk-example-boot")
{
    var session = Connect(url, user, password);
    var vm = VM.clone(session, TemplateByName(session, templateName), newVmName).opaque_ref;
    Provision(session, vm);

    VM.set_VCPUs_max(session, vm, 4);
    VM.set_VCPUs_at_startup(session, vm, 2);
    Console.WriteLine($"vCPUs: {VM.get_VCPUs_at_startup(session, vm)}/{VM.get_VCPUs_max(session, vm)}");

    // Boot mode: firmware ("bios"/"uefi") lives in HVM_boot_params; Secure Boot in
    // platform["secureboot"]. "auto" (not a hard-coded "true") is the xe convention:
    // xapi resolves it against whether the pool actually holds Secure Boot certificates, at
    // VM.start time - a hard "true" would claim Secure Boot is on even on a template that was never
    // set up for it, since set_platform does no validation of its own.
    VM.set_HVM_boot_params(session, vm, new Dictionary<string, string> { ["order"] = "cdn", ["firmware"] = "uefi" });
    var platform = VM.get_platform(session, vm);
    platform["secureboot"] = "auto";
    VM.set_platform(session, vm, platform);
    Console.WriteLine($"Boot order: {VM.get_HVM_boot_params(session, vm)["order"]}");
    Console.WriteLine($"Boot mode: firmware={VM.get_HVM_boot_params(session, vm)["firmware"]}, " +
                      $"secureboot={VM.get_platform(session, vm)["secureboot"]} " +
                      "(resolved against pool certificates at boot)");

    DestroyVmAndDisks(session, vm);
    Console.WriteLine("OK: vm-boot-config");
    session.logout();
}
```

<details><summary>Example output</summary>

```text
vCPUs: 2/4
Boot order: cdn
Boot mode: firmware=uefi, secureboot=auto (resolved against pool certificates at boot)
OK: vm-boot-config
```

</details>

## Python

Source: [`python/virtual_machines/vm_boot_config.py`](../../python/virtual_machines/vm_boot_config.py)

```python
"""VM boot configuration.

Set a VM's vCPU counts and boot order, then read them back.

Run it::

    vm_boot_config("https://xenserver", "root", password, "Rocky Linux 8")
"""

from connection import connect
from helpers import destroy_vm_and_disks, provision, template_by_name


def vm_boot_config(url, username, password, template_name, new_vm_name="sdk-example-boot"):
    """Provision a throwaway VM, then set its vCPU counts and boot order (HVM_boot_params)."""
    session = connect(url, username, password)
    vm = session.xenapi.VM.clone(template_by_name(session, template_name), new_vm_name)
    provision(session, vm)

    session.xenapi.VM.set_VCPUs_max(vm, "4")
    session.xenapi.VM.set_VCPUs_at_startup(vm, "2")
    print("vCPUs: %s/%s" %
          (session.xenapi.VM.get_VCPUs_at_startup(vm), session.xenapi.VM.get_VCPUs_max(vm)))

    # Boot mode: firmware ("bios"/"uefi") lives in HVM_boot_params; Secure Boot in
    # platform["secureboot"]. "auto" (not a hard-coded "true") is the xe
    # convention: xapi resolves it against whether the pool actually holds Secure
    # Boot certificates, at VM.start time - a hard "true" would claim Secure Boot
    # is on even on a template that was never set up for it, since set_platform
    # does no validation of its own.
    session.xenapi.VM.set_HVM_boot_params(vm, {"order": "cdn", "firmware": "uefi"})
    platform = session.xenapi.VM.get_platform(vm)
    platform["secureboot"] = "auto"
    session.xenapi.VM.set_platform(vm, platform)
    print("Boot order: %s" % session.xenapi.VM.get_HVM_boot_params(vm)["order"])
    print("Boot mode: firmware=%s, secureboot=%s (resolved against pool certificates at boot)" %
          (session.xenapi.VM.get_HVM_boot_params(vm)["firmware"],
           session.xenapi.VM.get_platform(vm)["secureboot"]))

    destroy_vm_and_disks(session, vm)
    print("OK: vm-boot-config")
    session.xenapi.session.logout()
```

<details><summary>Example output</summary>

```text
vCPUs: 2/4
Boot order: cdn
Boot mode: firmware=uefi, secureboot=auto (resolved against pool certificates at boot)
OK: vm-boot-config
```

</details>

## Java

Source: [`java/src/main/java/com/xenserver/samples/virtualmachines/VmBootConfig.java`](../../java/src/main/java/com/xenserver/samples/virtualmachines/VmBootConfig.java)

```java
package com.xenserver.samples.virtualmachines;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.Session;
import com.xensource.xenapi.VM;

import java.util.Map;

import static com.xenserver.samples.Helpers.destroyVmAndDisks;
import static com.xenserver.samples.Helpers.provision;
import static com.xenserver.samples.Helpers.templateByName;
import static com.xenserver.samples.PoolConnection.connect;

public final class VmBootConfig {
    private VmBootConfig() {
    }

    /**
     * VM boot configuration.
     *
     * <p>Set a VM's vCPU counts and boot order, then read them back.
     *
     * <p>Run it:
     *
     * <pre>{@code
     * VmBootConfig.run("https://xenserver", "root", password, "Rocky Linux 8", "sdk-example-boot");
     * }</pre>
     */
    public static void run(String url, String user, String password,
            String templateName, String newVmName) throws Exception {
        Connection conn = connect(url, user, password);
        VM vm = templateByName(conn, templateName).createClone(conn, newVmName);
        provision(conn, vm);

        vm.setVCPUsMax(conn, 4L);
        vm.setVCPUsAtStartup(conn, 2L);

        // Boot mode: firmware ("bios"/"uefi") lives in HVM_boot_params; Secure Boot in
        // platform["secureboot"]. "auto" (not a hard-coded "true") is the xe convention:
        // xapi resolves it against whether the pool actually holds Secure Boot certificates, at VM.start
        // time - a hard "true" would claim Secure Boot is on even on a template that was never set up for
        // it, since setPlatform does no validation of its own.
        Map<String, String> bootParams = new java.util.HashMap<>();
        bootParams.put("order", "cdn");
        bootParams.put("firmware", "uefi");
        vm.setHVMBootParams(conn, bootParams);
        Map<String, String> platform = vm.getPlatform(conn);
        platform.put("secureboot", "auto");
        vm.setPlatform(conn, platform);
        System.out.println("vCPUs: " + vm.getVCPUsAtStartup(conn) + "/" + vm.getVCPUsMax(conn));
        System.out.println("Boot order: " + vm.getHVMBootParams(conn).get("order"));
        System.out.println("Boot mode: firmware=" + vm.getHVMBootParams(conn).get("firmware")
                + ", secureboot=" + vm.getPlatform(conn).get("secureboot")
                + " (resolved against pool certificates at boot)");

        destroyVmAndDisks(conn, vm);
        System.out.println("OK: vm-boot-config");
        Session.logout(conn);
    }
}
```

<details><summary>Example output</summary>

```text
vCPUs: 2/4
Boot order: cdn
Boot mode: firmware=uefi, secureboot=auto (resolved against pool certificates at boot)
OK: vm-boot-config
```

</details>

## Go

Source: [`go/vm_boot_config.go`](../../go/vm_boot_config.go)

```go
package main

import (
	"fmt"

	"go/xenapi"
)

// vmBootConfig - VM boot configuration.
//
// Set a VM's vCPU counts and boot order, then read them back.
//
// Run it:
//
//	vmBootConfig("https://xenserver", "root", password, "Rocky Linux 8", "sdk-example-boot")
func vmBootConfig(url, user, password, templateName, newVMName string) {
	session := connect(url, user, password)
	vm, err := xenapi.VM.Clone(session, templateByName(session, templateName), newVMName)
	check(err)
	provision(session, vm)

	check(xenapi.VM.SetVCPUsMax(session, vm, 4))
	check(xenapi.VM.SetVCPUsAtStartup(session, vm, 2))

	// Boot mode: firmware ("bios"/"uefi") lives in HVM_boot_params; Secure Boot in
	// platform["secureboot"]. "auto" (not a hard-coded "true") is the xe convention:
	// xapi resolves it against whether the pool actually holds Secure Boot certificates, at
	// VM.start time - a hard "true" would claim Secure Boot is on even on a template that was never
	// set up for it, since set_platform does no validation of its own.
	check(xenapi.VM.SetHVMBootParams(session, vm, map[string]string{"order": "cdn", "firmware": "uefi"}))
	platform, _ := xenapi.VM.GetPlatform(session, vm)
	platform["secureboot"] = "auto"
	check(xenapi.VM.SetPlatform(session, vm, platform))
	atStartup, _ := xenapi.VM.GetVCPUsAtStartup(session, vm)
	max, _ := xenapi.VM.GetVCPUsMax(session, vm)
	fmt.Printf("vCPUs: %d/%d\n", atStartup, max)
	bootParams, _ := xenapi.VM.GetHVMBootParams(session, vm)
	fmt.Printf("Boot order: %s\n", bootParams["order"])
	platform, _ = xenapi.VM.GetPlatform(session, vm)
	fmt.Printf("Boot mode: firmware=%s, secureboot=%s (resolved against pool certificates at boot)\n",
		bootParams["firmware"], platform["secureboot"])

	destroyVMAndDisks(session, vm)
	fmt.Println("OK: vm-boot-config")
	session.Logout()
}
```

<details><summary>Example output</summary>

```text
vCPUs: 2/4
Boot order: cdn
Boot mode: firmware=uefi, secureboot=auto (resolved against pool certificates at boot)
OK: vm-boot-config
```

</details>

## PowerShell

Source: [`powershell/VirtualMachines/Invoke-VmBootConfig.ps1`](../../powershell/VirtualMachines/Invoke-VmBootConfig.ps1)

```powershell
function Invoke-VmBootConfig {
    <#
    .SYNOPSIS
        VM boot configuration.
    .DESCRIPTION
        Set a VM's vCPU counts and boot order, then read them back.
    .EXAMPLE
        Invoke-VmBootConfig -Url https://xenserver -UserName root -Password $password -TemplateName 'Rocky Linux 8'
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password,
        [Parameter(Mandatory = $true)][string]$TemplateName,
        [string]$NewVmName = "sdk-example-boot"
    )
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password
    $template = Get-XenVM -Name $TemplateName | Where-Object { $_.is_a_template } | Select-Object -First 1
    if (-not $template) { throw "No template named '$TemplateName' was found." }
    $vm = $template | Invoke-XenVM -XenAction Clone -NewName $NewVmName -PassThru
    Invoke-VmProvision -Ref $vm.opaque_ref
    $ref = $vm.opaque_ref

    # Set the vCPU topology and switch the VM to UEFI boot: firmware ("bios"/"uefi") lives in
    # HVM_boot_params, Secure Boot in platform["secureboot"]. "auto" (not a hard-coded "true") is the xe
    # convention: xapi resolves it against whether the pool actually holds Secure Boot certificates, at
    # VM.start time - a hard "true" would claim Secure Boot is on even on a template that was never set up for
    # it, since Set-XenVM does no validation of its own.
    $vm | Set-XenVM -VCPUsMax 4 -VCPUsAtStartup 2 -HVMBootParams @{ order = "cdn"; firmware = "uefi" }
    $platform = (Get-XenVM -Ref $ref).platform
    $platform["secureboot"] = "auto"
    $vm | Set-XenVM -Platform $platform

    $configured = Get-XenVM -Ref $ref
    Write-Host "vCPUs: $($configured.VCPUs_at_startup)/$($configured.VCPUs_max)"
    Write-Host "Boot order: $($configured.HVM_boot_params['order'])"
    Write-Host "Boot mode: firmware=$($configured.HVM_boot_params['firmware']), secureboot=$($configured.platform['secureboot']) (resolved against pool certificates at boot)"

    Remove-VmAndDisks -Ref $vm.opaque_ref
    Write-Host "OK: vm-boot-config"
    $session | Disconnect-XenServer
}
```

<details><summary>Example output</summary>

```text
vCPUs: 2/4
Boot order: cdn
Boot mode: firmware=uefi, secureboot=auto (resolved against pool certificates at boot)
OK: vm-boot-config
```

</details>

## xe CLI

Source: [`cli/virtual-machines/vm-boot-config.sh`](../../cli/virtual-machines/vm-boot-config.sh)

```bash
# VM boot configuration.
#
# Set a VM's vCPU counts and boot order, then read them back.
#
# Run it:
#   ./workflows.sh vm-boot-config https://xenserver root "$password"
#
# Optional key=value arguments (default):
#   template_name (Rocky Linux 8)

vm_boot_config() {
    local template=$(param template_name "Rocky Linux 8")
    vm=$(xe vm-install template="$template" new-name-label=xe-example-boot)
    xe vm-param-set uuid=$vm VCPUs-max=4 VCPUs-at-startup=2
    # Boot mode: firmware ("bios"/"uefi") lives in HVM-boot-params; Secure Boot in platform:secureboot.
    # "auto" (not a hard-coded "true") is the xe convention: xapi resolves it against
    # whether the pool actually holds Secure Boot certificates, at vm-start time - a hard "true" would
    # claim Secure Boot is on even on a template that was never set up for it, since platform:secureboot
    # does no validation of its own.
    xe vm-param-set uuid=$vm HVM-boot-params:order=cdn HVM-boot-params:firmware=uefi
    xe vm-param-set uuid=$vm platform:secureboot=auto
    echo "vCPUs: $(xe vm-param-get uuid=$vm param-name=VCPUs-at-startup)/$(xe vm-param-get uuid=$vm param-name=VCPUs-max)"
    echo "Boot order: $(xe vm-param-get uuid=$vm param-name=HVM-boot-params param-key=order)"
    echo "Boot mode: firmware=$(xe vm-param-get uuid=$vm param-name=HVM-boot-params param-key=firmware), secureboot=$(xe vm-param-get uuid=$vm param-name=platform param-key=secureboot) (resolved against pool certificates at boot)"
    # Tidy up so the example is repeatable: vm-uninstall destroys the VM and the disks it owns (vm-destroy
    # would leave the disks behind).
    xe vm-uninstall uuid=$vm force=true
    echo "OK: vm-boot-config"
}
```

<details><summary>Example output</summary>

```text
vCPUs: 2/4
Boot order: cdn
Boot mode: firmware=uefi, secureboot=auto (resolved against pool certificates at boot)
OK: vm-boot-config
```

</details>
