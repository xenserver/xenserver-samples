<!-- Generated from workflows.json, the example sources and a run of each example. Edit those, not this file. -->

# Manage Secure Boot certificates

Check whether the pool can supply UEFI Secure Boot certificates and whether a guest is ready to use them, then flag a guest whose certificates have gone stale for a refresh at its next boot — and unflag it again.

**Caution:** updating a guest's certificates can trigger BitLocker recovery (TPM PCR7 changes).

Workflow `manage-secureboot-certificates`. [All workflows](README.md) · [Connecting](connecting.md)

## C# (.NET)

Source: [`csharp/SecurityAndAccess/ManageSecurebootCertificates.cs`](../../csharp/SecurityAndAccess/ManageSecurebootCertificates.cs)

```csharp
/// <summary>
/// Check whether the pool can supply UEFI Secure Boot certificates and whether a guest is ready to use
/// them, then flag a guest whose certificates have gone stale for a refresh at its next boot — and unflag
/// it again.
/// </summary>
/// <remarks>
/// Caution: updating a guest's certificates changes its TPM PCR7 measurements, which can trigger
/// BitLocker recovery on a Windows guest at its next boot. Keep BitLocker recovery keys to hand,
/// suspend BitLocker on affected VMs first, and do the refresh in a monitored maintenance window.
/// </remarks>
/// <example>
/// <code>
/// Workflows.ManageSecurebootCertificates("https://xenserver", "root", password);
/// </code>
/// </example>
public static void ManageSecurebootCertificates(string url, string user, string password)
{
    var session = Connect(url, user, password);
    var pool = Pool.get_all(session).First().opaque_ref;

    // A Secure Boot guest carries its own copy of the pool's UEFI certificates, taken when it was
    // created. Rotating the pool's leaves the guest's stale, and the fix is applied at the guest's
    // next boot rather than underneath a running VM — so you flag it and reboot when convenient.
    //
    // First, whether the pool holds the certificates to hand out at all. "ready_no_dbx" means it has
    // the essentials but no revocation list — usable, and not the same answer as "ready".
    Console.WriteLine($"Pool Secure Boot readiness: {Pool.get_guest_secureboot_readiness(session, pool)}");
    Console.WriteLine("  pool holds certificates:  "
                      + !string.IsNullOrEmpty(Pool.get_uefi_certificates(session, pool)));

    // A guest whose certificates have gone stale. Its state is what a client gates the flag/unflag
    // actions on, so it is the field to watch. This is a deliberately-provisioned state, not one a
    // normally-provisioned Secure Boot guest is ever in - so report and stop cleanly rather than
    // letting a bare "no such element" lookup error propagate when nothing needs it right now.
    var candidate = VM.get_all_records(session).FirstOrDefault(kv =>
        !kv.Value.is_a_template && !kv.Value.is_control_domain && !kv.Value.is_a_snapshot
        && kv.Value.secureboot_certificates_state == vm_secureboot_certificates_state.update_available);
    if (candidate.Key == null)
    {
        Console.WriteLine("No guest needs a Secure Boot certificate refresh right now.");
        Console.WriteLine("OK: manage-secureboot-certificates");
        session.logout();
        return;
    }
    var vm = candidate.Key.opaque_ref;
    Console.WriteLine($"{VM.get_name_label(session, vm)}: readiness "
                      + $"{VM.get_secureboot_readiness(session, vm)}, certificates "
                      + $"{VM.get_secureboot_certificates_state(session, vm)}");

    // Flagging and unflagging are the same call with opposite booleans.
    VM.update_secureboot_certificates_on_boot(session, vm, true);
    Console.WriteLine($"  flagged for refresh:      {VM.get_secureboot_certificates_state(session, vm)}");

    VM.update_secureboot_certificates_on_boot(session, vm, false);
    Console.WriteLine($"  unflagged:                {VM.get_secureboot_certificates_state(session, vm)}");

    Console.WriteLine("OK: manage-secureboot-certificates");
    session.logout();
}
```

<details><summary>Example output</summary>

```text
Pool Secure Boot readiness: ready_no_dbx
  pool holds certificates:  True
secure-01: readiness ready_no_dbx, certificates update_available
  flagged for refresh:      update_on_boot
  unflagged:                update_available
OK: manage-secureboot-certificates
```

</details>

## Python

Source: [`python/security_and_access/manage_secureboot_certificates.py`](../../python/security_and_access/manage_secureboot_certificates.py)

```python
"""Manage Secure Boot certificates.

Check whether the pool can supply UEFI Secure Boot certificates and whether a guest is ready to use
them, then flag a guest whose certificates have gone stale for a refresh at its next boot — and
unflag it again.

Run it::

    manage_secureboot_certificates("https://xenserver", "root", password)
"""

from connection import connect


def manage_secureboot_certificates(url, username, password):
    """Check UEFI Secure Boot readiness, then flag a guest for a certificate refresh.

    A Secure Boot guest carries its own copy of the pool's UEFI certificates, taken when it
    was created. Rotating the pool's leaves the guest's stale, and the fix is applied at the
    guest's next boot rather than underneath a running VM -- so you flag it and reboot when
    convenient. Flagging and unflagging are the same call with opposite booleans.

    The precondition is the part worth being honest about: this needs a VM whose Secure Boot
    certificates are already due to refresh (secureboot_certificates_state == update_available).
    That's a deliberately-provisioned state, not one a normally-provisioned Secure Boot guest is
    ever in - so report and stop cleanly when no VM needs it, rather than failing with a bare
    lookup error.

    Caution: updating a guest's certificates changes its TPM PCR7 measurements, which can trigger
    BitLocker recovery on a Windows guest at its next boot. Keep BitLocker recovery keys to hand,
    suspend BitLocker on affected VMs first, and do the refresh in a monitored maintenance window."""
    session = connect(url, username, password)
    x = session.xenapi
    pool = x.pool.get_all()[0]

    # Whether the pool holds the certificates to hand out at all. "ready_no_dbx" means it has
    # the essentials but no revocation list -- usable, and not the same answer as "ready".
    print("Pool Secure Boot readiness: %s" % x.pool.get_guest_secureboot_readiness(pool))
    print("  pool holds certificates:  %s" % bool(x.pool.get_uefi_certificates(pool)))

    # A guest whose certificates have gone stale. Its state is what a client gates the
    # flag/unflag actions on, so it is the field to watch.
    vm = next((ref for ref, r in x.VM.get_all_records().items()
               if not r["is_a_template"] and not r["is_control_domain"] and not r["is_a_snapshot"]
               and r["secureboot_certificates_state"] == "update_available"), None)
    if vm is None:
        print("No guest needs a Secure Boot certificate refresh right now.")
        print("OK: manage-secureboot-certificates")
        session.logout()
        return
    print("%s: readiness %s, certificates %s"
          % (x.VM.get_name_label(vm), x.VM.get_secureboot_readiness(vm),
             x.VM.get_secureboot_certificates_state(vm)))

    x.VM.update_secureboot_certificates_on_boot(vm, True)
    print("  flagged for refresh:      %s" % x.VM.get_secureboot_certificates_state(vm))

    x.VM.update_secureboot_certificates_on_boot(vm, False)
    print("  unflagged:                %s" % x.VM.get_secureboot_certificates_state(vm))

    print("OK: manage-secureboot-certificates")
    session.logout()
```

<details><summary>Example output</summary>

```text
Pool Secure Boot readiness: ready_no_dbx
  pool holds certificates:  True
secure-01: readiness ready_no_dbx, certificates update_available
  flagged for refresh:      update_on_boot
  unflagged:                update_available
OK: manage-secureboot-certificates
```

</details>

## Java

Source: [`java/src/main/java/com/xenserver/samples/securityandaccess/ManageSecurebootCertificates.java`](../../java/src/main/java/com/xenserver/samples/securityandaccess/ManageSecurebootCertificates.java)

```java
package com.xenserver.samples.securityandaccess;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.Pool;
import com.xensource.xenapi.Session;
import com.xensource.xenapi.Types;
import com.xensource.xenapi.VM;

import java.util.Map;

import static com.xenserver.samples.PoolConnection.connect;

public final class ManageSecurebootCertificates {
    private ManageSecurebootCertificates() {
    }

    /**
     * Manage Secure Boot certificates.
     *
     * <p>Check whether the pool can supply UEFI Secure Boot certificates and whether a guest is ready to
     * use them, then flag a guest whose certificates have gone stale for a refresh at its next boot — and
     * unflag it again.
     *
     * <p>Caution: updating a guest's certificates changes its TPM PCR7 measurements, which can trigger
     * BitLocker recovery on a Windows guest at its next boot. Keep BitLocker recovery keys to hand,
     * suspend BitLocker on affected VMs first, and do the refresh in a monitored maintenance window.
     *
     * <p>Run it:
     *
     * <pre>{@code
     * ManageSecurebootCertificates.run("https://xenserver", "root", password);
     * }</pre>
     */
    public static void run(String url, String user, String password) throws Exception {
        Connection conn = connect(url, user, password);
        try {
            Pool pool = Pool.getAll(conn).iterator().next();

            // A Secure Boot guest carries its own copy of the pool's UEFI certificates, taken when it
            // was created. Rotating the pool's leaves the guest's stale, and the fix is applied at the
            // guest's next boot rather than underneath a running VM - so you flag it and reboot when
            // convenient.
            //
            // First, whether the pool holds the certificates to hand out at all. "ready_no_dbx" means it
            // has the essentials but no revocation list - usable, and not the same answer as "ready".
            System.out.println("Pool Secure Boot readiness: " + pool.getGuestSecurebootReadiness(conn));
            System.out.println("  pool holds certificates:  "
                + !pool.getUefiCertificates(conn).isEmpty());

            // A guest whose certificates have gone stale. Its state is what a client gates the
            // flag/unflag actions on, so it is the field to watch.
            VM vm = null;
            String name = null;
            for (Map.Entry<VM, VM.Record> e : VM.getAllRecords(conn).entrySet()) {
                VM.Record r = e.getValue();
                if (!r.isATemplate && !r.isControlDomain && !r.isASnapshot
                        && r.securebootCertificatesState == Types.VmSecurebootCertificatesState.UPDATE_AVAILABLE) {
                    vm = e.getKey(); name = r.nameLabel; break;
                }
            }
            if (vm == null) {
                // The precondition is the part worth being honest about: this needs a VM whose Secure
                // Boot certificates are already due to refresh. That's a deliberately-provisioned state,
                // not one a normally-provisioned Secure Boot guest is ever in - so report and stop cleanly
                // rather than failing with a bare lookup error.
                System.out.println("No guest needs a Secure Boot certificate refresh right now.");
                System.out.println("OK: manage-secureboot-certificates");
                return;
            }
            System.out.printf("%s: readiness %s, certificates %s%n", name,
                vm.getSecurebootReadiness(conn), vm.getSecurebootCertificatesState(conn));

            // Flagging and unflagging are the same call with opposite booleans.
            vm.updateSecurebootCertificatesOnBoot(conn, true);
            System.out.println("  flagged for refresh:      " + vm.getSecurebootCertificatesState(conn));

            vm.updateSecurebootCertificatesOnBoot(conn, false);
            System.out.println("  unflagged:                " + vm.getSecurebootCertificatesState(conn));

            System.out.println("OK: manage-secureboot-certificates");
        } finally {
            Session.logout(conn);
        }
    }
}
```

<details><summary>Example output</summary>

```text
Pool Secure Boot readiness: ready_no_dbx
  pool holds certificates:  true
secure-01: readiness ready_no_dbx, certificates update_available
  flagged for refresh:      update_on_boot
  unflagged:                update_available
OK: manage-secureboot-certificates
```

</details>

## Go

Source: [`go/manage_secureboot_certificates.go`](../../go/manage_secureboot_certificates.go)

```go
package main

import (
	"fmt"

	"go/xenapi"
)

// manageSecurebootCertificates - Manage Secure Boot certificates.
//
// Check whether the pool can supply UEFI Secure Boot certificates and whether a guest is ready to
// use them, then flag a guest whose certificates have gone stale for a refresh at its next boot —
// and unflag it again.
//
// Caution: updating a guest's certificates changes its TPM PCR7 measurements, which can trigger
// BitLocker recovery on a Windows guest at its next boot. Keep BitLocker recovery keys to hand,
// suspend BitLocker on affected VMs first, and do the refresh in a monitored maintenance window.
//
// Run it:
//
//	manageSecurebootCertificates("https://xenserver", "root", password)
func manageSecurebootCertificates(url, user, password string) {
	session := connect(url, user, password)
	defer session.Logout()

	// A Secure Boot guest carries its own copy of the pool's UEFI certificates, taken when it was
	// created. Rotating the pool's leaves the guest's stale, and the fix is applied at the guest's next
	// boot rather than underneath a running VM - so you flag it and reboot when convenient.
	//
	// First, whether the pool holds the certificates to hand out at all. "ready_no_dbx" means it has the
	// essentials but no revocation list - usable, and not the same answer as "ready".
	pools, err := xenapi.Pool.GetAll(session)
	check(err)
	readiness, err := xenapi.Pool.GetGuestSecurebootReadiness(session, pools[0])
	check(err)
	certs, err := xenapi.Pool.GetUefiCertificates(session, pools[0])
	check(err)
	fmt.Printf("Pool Secure Boot readiness: %s\n", readiness)
	fmt.Printf("  pool holds certificates:  %t\n", certs != "")

	// A guest whose certificates have gone stale. Its state is what a client gates the flag/unflag
	// actions on, so it is the field to watch. This is a deliberately-provisioned state, not one a
	// normally-provisioned Secure Boot guest is ever in - report and stop cleanly when no VM needs
	// it, rather than failing with a bare lookup error.
	vms, err := xenapi.VM.GetAllRecords(session)
	check(err)
	var vm xenapi.VMRef
	var name string
	found := false
	for ref, r := range vms {
		if !r.IsATemplate && !r.IsControlDomain && !r.IsASnapshot &&
			r.SecurebootCertificatesState == xenapi.VMSecurebootCertificatesStateUpdateAvailable {
			vm, name, found = ref, r.NameLabel, true
			break
		}
	}
	if !found {
		fmt.Println("No guest needs a Secure Boot certificate refresh right now.")
		fmt.Println("OK: manage-secureboot-certificates")
		return
	}
	vmReadiness, err := xenapi.VM.GetSecurebootReadiness(session, vm)
	check(err)
	state, err := xenapi.VM.GetSecurebootCertificatesState(session, vm)
	check(err)
	fmt.Printf("%s: readiness %s, certificates %s\n", name, vmReadiness, state)

	// Flagging and unflagging are the same call with opposite booleans.
	check(xenapi.VM.UpdateSecurebootCertificatesOnBoot(session, vm, true))
	state, _ = xenapi.VM.GetSecurebootCertificatesState(session, vm)
	fmt.Printf("  flagged for refresh:      %s\n", state)

	check(xenapi.VM.UpdateSecurebootCertificatesOnBoot(session, vm, false))
	state, _ = xenapi.VM.GetSecurebootCertificatesState(session, vm)
	fmt.Printf("  unflagged:                %s\n", state)

	fmt.Println("OK: manage-secureboot-certificates")
}
```

<details><summary>Example output</summary>

```text
Pool Secure Boot readiness: ready_no_dbx
  pool holds certificates:  true
secure-01: readiness ready_no_dbx, certificates update_available
  flagged for refresh:      update_on_boot
  unflagged:                update_available
OK: manage-secureboot-certificates
```

</details>

## PowerShell

Source: [`powershell/SecurityAndAccess/Invoke-ManageSecurebootCertificates.ps1`](../../powershell/SecurityAndAccess/Invoke-ManageSecurebootCertificates.ps1)

```powershell
function Invoke-ManageSecurebootCertificates {
    <#
    .SYNOPSIS
        Manage Secure Boot certificates.
    .DESCRIPTION
        Check whether the pool can supply UEFI Secure Boot certificates and whether a guest is ready to use
        them, then flag a guest whose certificates have gone stale for a refresh at its next boot — and
        unflag it again.

        Caution: updating a guest's certificates changes its TPM PCR7 measurements, which can trigger
        BitLocker recovery on a Windows guest at its next boot. Keep BitLocker recovery keys to hand,
        suspend BitLocker on affected VMs first, and do the refresh in a monitored maintenance window.
    .EXAMPLE
        Invoke-ManageSecurebootCertificates -Url https://xenserver -UserName root -Password $password
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password
    )
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password
    $pool = Get-XenPool | Select-Object -First 1

    # A Secure Boot guest carries its own copy of the pool's UEFI certificates, taken when it was created.
    # Rotating the pool's leaves the guest's stale, and the fix is applied at the guest's next boot rather
    # than underneath a running VM - so you flag it and reboot when convenient.
    #
    # First, whether the pool holds the certificates to hand out at all. "ready_no_dbx" means it has the
    # essentials but no revocation list - usable, and not the same answer as "ready".
    Write-Host "Pool Secure Boot readiness: $(Get-XenPoolProperty -Ref $pool.opaque_ref -XenProperty GuestSecurebootReadiness)"
    Write-Host "  pool holds certificates:  $([bool]$pool.uefi_certificates)"

    # A guest whose certificates have gone stale. Its state is what a client gates the flag/unflag actions
    # on, so it is the field to watch.
    $vm = Get-XenVM | Where-Object {
        -not $_.is_a_template -and -not $_.is_control_domain -and -not $_.is_a_snapshot -and
        $_.secureboot_certificates_state -eq 'update_available'
    } | Select-Object -First 1
    if (-not $vm) {
        # This state only occurs on a VM whose UEFI certificates are out of date, not on a normally
        # provisioned pool. Report cleanly instead of letting a bare "no such element" lookup error
        # propagate.
        Write-Host "No guest needs a Secure Boot certificate refresh right now."
        Write-Host "OK: manage-secureboot-certificates"
        $session | Disconnect-XenServer
        return
    }
    Write-Host ("{0}: readiness {1}, certificates {2}" -f $vm.name_label,
        (Get-XenVMProperty -Ref $vm.opaque_ref -XenProperty SecurebootReadiness),
        (Get-XenVMProperty -Ref $vm.opaque_ref -XenProperty SecurebootCertificatesState))

    # Flagging and unflagging are the same action with opposite values of -Mark.
    $vm | Invoke-XenVM -XenAction UpdateSecurebootCertificatesOnBoot -Mark $true
    Write-Host "  flagged for refresh:      $((Get-XenVM -Ref $vm.opaque_ref).secureboot_certificates_state)"

    $vm | Invoke-XenVM -XenAction UpdateSecurebootCertificatesOnBoot -Mark $false
    Write-Host "  unflagged:                $((Get-XenVM -Ref $vm.opaque_ref).secureboot_certificates_state)"

    Write-Host "OK: manage-secureboot-certificates"
    $session | Disconnect-XenServer
}
```

<details><summary>Example output</summary>

```text
Pool Secure Boot readiness: ready_no_dbx
  pool holds certificates:  True
secure-01: readiness ready_no_dbx, certificates update_available
  flagged for refresh:      update_on_boot
  unflagged:                update_available
OK: manage-secureboot-certificates
```

</details>

## xe CLI

Source: [`cli/security-and-access/manage-secureboot-certificates.sh`](../../cli/security-and-access/manage-secureboot-certificates.sh)

```bash
# Manage Secure Boot certificates.
#
# Check whether the pool can supply UEFI Secure Boot certificates and whether a guest is ready to use them,
# then flag a guest whose certificates have gone stale for a refresh at its next boot — and unflag it again.
#
# Run it:
#   ./workflows.sh manage-secureboot-certificates https://xenserver root "$password"

manage_secureboot_certificates() {
    # A Secure Boot guest carries its own copy of the pool's UEFI certificates, taken when it was created.
    # Rotating the pool's leaves the guest's stale, and the fix is applied at the guest's next boot rather
    # than underneath a running VM - so you flag it and reboot when convenient.
    #
    # "ready_no_dbx" means the pool has the essentials but no revocation list - usable, and deliberately
    # not the same answer as "ready".
    echo "Pool Secure Boot readiness: $(xe pool-get-guest-secureboot-readiness)"
    pool=$(first_csv "$(xe pool-list --minimal)")
    if [ -n "$(xe pool-param-get uuid=$pool param-name=uefi-certificates)" ]; then holds=true; else holds=false; fi
    echo "  pool holds certificates:  $holds"

    # A guest whose certificates have gone stale. The state is a plain field, so it filters like any other.
    # This is a deliberately-seeded state, not one an ordinarily-provisioned pool is ever in - report and
    # stop cleanly when no VM needs it, rather than operating on an empty uuid.
    #
    # Caution: updating a guest's certificates changes its TPM PCR7 measurements, which can trigger
    # BitLocker recovery on a Windows guest at its next boot. Keep BitLocker recovery keys to hand,
    # suspend BitLocker on affected VMs first, and do the refresh in a monitored maintenance window.
    vm=$(first_csv "$(xe vm-list secureboot-certificates-state=update_available --minimal)")
    if [ -z "$vm" ]; then
        echo "No guest needs a Secure Boot certificate refresh right now."
        echo "OK: manage-secureboot-certificates"
        return
    fi
    echo "$(xe vm-param-get uuid=$vm param-name=name-label): readiness $(xe vm-get-secureboot-readiness uuid=$vm), certificates $(xe vm-param-get uuid=$vm param-name=secureboot-certificates-state)"

    # Flagging and unflagging are the same command with opposite values of mark=.
    xe vm-update-secureboot-certificates-on-boot uuid=$vm mark=true
    echo "  flagged for refresh:      $(xe vm-param-get uuid=$vm param-name=secureboot-certificates-state)"

    xe vm-update-secureboot-certificates-on-boot uuid=$vm mark=false
    echo "  unflagged:                $(xe vm-param-get uuid=$vm param-name=secureboot-certificates-state)"
    echo "OK: manage-secureboot-certificates"
}
```

<details><summary>Example output</summary>

```text
Pool Secure Boot readiness: ready_no_dbx
  pool holds certificates:  true
secure-01: readiness ready_no_dbx, certificates update_available
  flagged for refresh:      update_on_boot
  unflagged:                update_available
OK: manage-secureboot-certificates
```

</details>
