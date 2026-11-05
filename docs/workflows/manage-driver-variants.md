<!-- Generated from workflows.json, the example sources and a run of each example. Edit those, not this file. -->

# Manage device driver variants

Inspect a host's device drivers and choose which variant of one to use, seeing the difference between the variant that is selected and the one currently loaded.

Workflow `manage-driver-variants`. [All workflows](README.md) · [Connecting](connecting.md)

## C# (.NET)

Source: [`csharp/HostsAndPools/ManageDriverVariants.cs`](../../csharp/HostsAndPools/ManageDriverVariants.cs)

```csharp
/// <summary>
/// Inspect a host's device drivers and choose which variant of one to use, seeing the difference between
/// the variant that is selected and the one currently loaded.
/// </summary>
public static void ManageDriverVariants(string url, string user, string password)
{
    var session = Connect(url, user, password);
    var host = Pool.get_master(session, Pool.get_all(session)[0].opaque_ref).opaque_ref;

    // A driver can ship in several variants — a vendor build alongside the one in the
    // distribution, say. One is SELECTED (what the host will load) and one is ACTIVE (what it has
    // loaded); they differ until the host reboots, which is what makes selecting a variant a
    // scheduled change rather than an immediate one.
    var drivers = Host_driver.get_all_records(session)
        .Where(kv => kv.Value.host.opaque_ref == host)
        .OrderBy(kv => kv.Value.name).ToList();
    Console.WriteLine($"{Host.get_name_label(session, host)} has {drivers.Count} driver(s)");
    foreach (var (_, driver) in drivers.Take(3))
        Console.WriteLine($"  {driver.name,-14} {driver.type,-10} {driver.variants.Count} variant(s), " +
            $"active={VariantName(session, driver.active_variant.opaque_ref)}");

    // Select a variant explicitly. It becomes the selected one immediately; whether it is also
    // active depends on whether the hardware is present and the driver already loaded.
    // Host_driver.select refuses a variant whose hardware isn't present (HOST_DRIVER_NO_HARDWARE) -
    // and a host lists drivers for plenty of devices it doesn't have - so pick a driver for
    // hardware this host actually has, and one of its variants that is usable.
    var usable = drivers
        .SelectMany(kv => kv.Value.variants.Select(v => (driverRef: kv.Key, variant: v)))
        .Where(p => Driver_variant.get_hardware_present(session, p.variant.opaque_ref))
        .ToList();
    if (usable.Count == 0)
        throw new Exception($"no driver on {Host.get_name_label(session, host)} has a variant for hardware it has");
    var (chosenRef, chosenVariant) = usable[0];
    var variant = chosenVariant.opaque_ref;
    Host_driver.select(session, chosenRef.opaque_ref, variant);
    var after = Host_driver.get_record(session, chosenRef.opaque_ref);
    Console.WriteLine($"  {after.name}: selected {VariantName(session, after.selected_variant.opaque_ref)}, " +
        $"active {VariantName(session, after.active_variant.opaque_ref)}");

    Console.WriteLine("OK: manage-driver-variants");
    session.logout();
}

/// <summary>A driver variant's name, tolerating the null reference an unloaded driver has.</summary>
private static string VariantName(Session session, string variantRef) =>
    !string.IsNullOrEmpty(variantRef) && variantRef != "OpaqueRef:NULL"
        ? Driver_variant.get_name(session, variantRef) : "(none)";
```

<details><summary>Example output</summary>

```text
sdk-host1 has 5 driver(s)
  ahci           storage    1 variant(s), active=generic
  bnxt_en        network    1 variant(s), active=generic
  i40e           network    1 variant(s), active=(none)
  ahci: selected generic, active generic
OK: manage-driver-variants
```

</details>

## Python

Source: [`python/hosts_and_pools/manage_driver_variants.py`](../../python/hosts_and_pools/manage_driver_variants.py)

```python
"""Manage device driver variants.

Inspect a host's device drivers and choose which variant of one to use, seeing the difference
between the variant that is selected and the one currently loaded.
"""

from connection import connect


def manage_driver_variants(url, username, password):
    """Inspect a host's device drivers and choose which variant of one to use.

    A driver can ship in several variants -- a vendor build alongside the one in the
    distribution, say. One is *selected* (what the host will load) and one is *active* (what it
    has loaded); they differ until the host reboots, which is what makes selecting a variant a
    scheduled change rather than an immediate one."""
    session = connect(url, username, password)
    x = session.xenapi
    host = x.pool.get_master(x.pool.get_all()[0])

    drivers = {ref: r for ref, r in x.Host_driver.get_all_records().items() if r["host"] == host}
    print("%s has %d driver(s)" % (x.host.get_name_label(host), len(drivers)))
    for ref, driver in sorted(drivers.items(), key=lambda kv: kv[1]["name"])[:3]:
        print("  %-14s %-10s %d variant(s), active=%s"
              % (driver["name"], driver["type"], len(driver["variants"]),
                 variant_name(x, driver["active_variant"])))

    # Select a variant explicitly. It becomes the selected one immediately; whether it is also
    # active depends on whether the hardware is present and the driver already loaded.
    # Host_driver.select refuses a variant whose hardware isn't present (HOST_DRIVER_NO_HARDWARE) -
    # and a host lists drivers for plenty of devices it doesn't have - so pick a driver for hardware
    # this host actually has, and one of its variants that is usable.
    usable = [(ref, v) for ref, d in sorted(drivers.items(), key=lambda kv: kv[1]["name"])
              for v in d["variants"] if x.Driver_variant.get_hardware_present(v)]
    if not usable:
        raise RuntimeError("no driver on %s has a variant for hardware it has" % x.host.get_name_label(host))
    ref, variant = usable[0]
    x.Host_driver.select(ref, variant)
    after = x.Host_driver.get_record(ref)
    print("  %s: selected %s, active %s"
          % (after["name"], variant_name(x, after["selected_variant"]),
             variant_name(x, after["active_variant"])))

    print("OK: manage-driver-variants")
    session.logout()


def variant_name(x, ref):
    """A driver variant's name, tolerating the null reference an unloaded driver has."""
    return x.Driver_variant.get_name(ref) if ref and ref != "OpaqueRef:NULL" else "(none)"
```

<details><summary>Example output</summary>

```text
sdk-host1 has 5 driver(s)
  ahci           storage    1 variant(s), active=generic
  bnxt_en        network    1 variant(s), active=generic
  i40e           network    1 variant(s), active=(none)
  ahci: selected generic, active generic
OK: manage-driver-variants
```

</details>

## Java

Source: [`java/src/main/java/com/xenserver/samples/hostsandpools/ManageDriverVariants.java`](../../java/src/main/java/com/xenserver/samples/hostsandpools/ManageDriverVariants.java)

```java
package com.xenserver.samples.hostsandpools;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.DriverVariant;
import com.xensource.xenapi.Host;
import com.xensource.xenapi.HostDriver;
import com.xensource.xenapi.Pool;
import com.xensource.xenapi.Session;

import java.util.Map;

import static com.xenserver.samples.PoolConnection.connect;

public final class ManageDriverVariants {
    private ManageDriverVariants() {
    }

    /**
     * Manage device driver variants.
     *
     * <p>Inspect a host's device drivers and choose which variant of one to use, seeing the difference
     * between the variant that is selected and the one currently loaded.
     */
    public static void run(String url, String user, String password) throws Exception {
        Connection conn = connect(url, user, password);
        try {
            // A driver can ship in several variants - a vendor build alongside the one in the
            // distribution, say. One is SELECTED (what the host will load) and one is ACTIVE (what it
            // has loaded); they differ until the host reboots, which is what makes selecting a variant a
            // scheduled change rather than an immediate one.
            Host host = Pool.getAll(conn).iterator().next().getMaster(conn);

            java.util.List<Map.Entry<HostDriver, HostDriver.Record>> drivers = new java.util.ArrayList<>();
            for (Map.Entry<HostDriver, HostDriver.Record> e : HostDriver.getAllRecords(conn).entrySet())
                if (e.getValue().host.equals(host)) drivers.add(e);
            drivers.sort(java.util.Comparator.comparing(e -> e.getValue().name));
            System.out.println(host.getNameLabel(conn) + " has " + drivers.size() + " driver(s)");
            for (Map.Entry<HostDriver, HostDriver.Record> e : drivers.subList(0, Math.min(3, drivers.size()))) {
                HostDriver.Record d = e.getValue();
                System.out.printf("  %-14s %-10s %d variant(s), active=%s%n",
                    d.name, d.type, d.variants.size(), variantName(conn, d.activeVariant));
            }

            // Select a variant explicitly. It becomes the selected one immediately; whether it is also
            // active depends on whether the hardware is present and the driver already loaded.
            // Host_driver.select refuses a variant whose hardware isn't present (HOST_DRIVER_NO_HARDWARE)
            // - and a host lists drivers for plenty of devices it doesn't have - so pick a driver for
            // hardware this host actually has, and one of its variants that is usable.
            HostDriver driverRef = null;
            DriverVariant variant = null;
            outer:
            for (Map.Entry<HostDriver, HostDriver.Record> e : drivers) {
                for (DriverVariant candidate : e.getValue().variants) {
                    if (candidate.getHardwarePresent(conn)) {
                        driverRef = e.getKey();
                        variant = candidate;
                        break outer;
                    }
                }
            }
            if (driverRef == null)
                throw new RuntimeException("no driver on " + host.getNameLabel(conn)
                        + " has a variant for hardware it has");
            driverRef.select(conn, variant);
            HostDriver.Record after = driverRef.getRecord(conn);
            System.out.printf("  %s: selected %s, active %s%n",
                after.name, variantName(conn, after.selectedVariant), variantName(conn, after.activeVariant));

            System.out.println("OK: manage-driver-variants");
        } finally {
            Session.logout(conn);
        }
    }

    /**
     * A driver variant's name, tolerating the null reference an unloaded driver has.
     */
    private static String variantName(Connection conn, DriverVariant variant) throws Exception {
        if (variant == null || variant.toWireString() == null
                || variant.toWireString().equals("OpaqueRef:NULL"))
            return "(none)";
        return variant.getName(conn);
    }
}
```

<details><summary>Example output</summary>

```text
sdk-host1 has 5 driver(s)
  ahci           storage    1 variant(s), active=generic
  bnxt_en        network    1 variant(s), active=generic
  i40e           network    1 variant(s), active=(none)
  ahci: selected generic, active generic
OK: manage-driver-variants
```

</details>

## Go

Source: [`go/manage_driver_variants.go`](../../go/manage_driver_variants.go)

```go
package main

import (
	"fmt"
	"sort"

	"go/xenapi"
)

// manageDriverVariants - Manage device driver variants.
//
// Inspect a host's device drivers and choose which variant of one to use, seeing the difference
// between the variant that is selected and the one currently loaded.
//
// A driver can ship in several variants - a vendor build alongside the one in the distribution, say.
// One is SELECTED (what the host will load) and one is ACTIVE (what it has loaded); they differ
// until the host reboots, which is what makes selecting a variant a scheduled change rather than an
// immediate one.
func manageDriverVariants(url, user, password string) {
	session := connect(url, user, password)
	defer session.Logout()

	pools, err := xenapi.Pool.GetAll(session)
	check(err)
	host, err := xenapi.Pool.GetMaster(session, pools[0])
	check(err)
	hostName, err := xenapi.Host.GetNameLabel(session, host)
	check(err)

	all, err := xenapi.HostDriver.GetAllRecords(session)
	check(err)
	drivers := map[xenapi.HostDriverRef]xenapi.HostDriverRecord{}
	var refs []xenapi.HostDriverRef
	for ref, r := range all {
		if r.Host != host {
			continue
		}
		drivers[ref] = r
		refs = append(refs, ref)
	}
	fmt.Printf("%s has %d driver(s)\n", hostName, len(refs))

	sort.Slice(refs, func(i, j int) bool { return drivers[refs[i]].Name < drivers[refs[j]].Name })
	shown := refs
	if len(shown) > 3 {
		shown = shown[:3]
	}
	for _, ref := range shown {
		d := drivers[ref]
		fmt.Printf("  %-14s %-10s %d variant(s), active=%s\n",
			d.Name, d.Type, len(d.Variants), variantName(session, d.ActiveVariant))
	}

	// Select a variant explicitly. It becomes the selected one immediately; whether it is also active
	// depends on whether the hardware is present and the driver already loaded.
	// Host_driver.select refuses a variant whose hardware isn't present (HOST_DRIVER_NO_HARDWARE) -
	// and a host lists drivers for plenty of devices it doesn't have - so pick a driver for hardware
	// this host actually has, and one of its variants that is usable.
	var chosenDriver xenapi.HostDriverRef
	var chosenVariant xenapi.DriverVariantRef
	found := false
	for _, ref := range refs {
		for _, v := range drivers[ref].Variants {
			if present, _ := xenapi.DriverVariant.GetHardwarePresent(session, v); present {
				chosenDriver, chosenVariant, found = ref, v, true
				break
			}
		}
		if found {
			break
		}
	}
	if !found {
		panic(fmt.Sprintf("no driver on %s has a variant for hardware it has", hostName))
	}
	check(xenapi.HostDriver.Select(session, chosenDriver, chosenVariant))
	after, err := xenapi.HostDriver.GetRecord(session, chosenDriver)
	check(err)
	fmt.Printf("  %s: selected %s, active %s\n",
		after.Name, variantName(session, after.SelectedVariant), variantName(session, after.ActiveVariant))

	fmt.Println("OK: manage-driver-variants")
}

// variantName is a driver variant's name, tolerating the null reference an unloaded driver has.
func variantName(session *xenapi.Session, ref xenapi.DriverVariantRef) string {
	if ref == "" || ref == "OpaqueRef:NULL" {
		return "(none)"
	}
	name, err := xenapi.DriverVariant.GetName(session, ref)
	check(err)
	return name
}
```

<details><summary>Example output</summary>

```text
sdk-host1 has 5 driver(s)
  ahci           storage    1 variant(s), active=generic
  bnxt_en        network    1 variant(s), active=generic
  i40e           network    1 variant(s), active=(none)
  ahci: selected generic, active generic
OK: manage-driver-variants
```

</details>

## PowerShell

Source: [`powershell/HostsAndPools/Invoke-ManageDriverVariants.ps1`](../../powershell/HostsAndPools/Invoke-ManageDriverVariants.ps1)

```powershell
function Invoke-ManageDriverVariants {
    <#
    .SYNOPSIS
        Manage device driver variants.
    .DESCRIPTION
        Inspect a host's device drivers and choose which variant of one to use, seeing the difference
        between the variant that is selected and the one currently loaded.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password
    )
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password
    $xenHost = Get-XenHost -Ref (Get-XenPool | Select-Object -First 1).master.opaque_ref

    # A driver can ship in several variants - a vendor build alongside the one in the distribution, say.
    # One is SELECTED (what the host will load) and one is ACTIVE (what it has loaded); they differ
    # until the host reboots, which is what makes selecting a variant a scheduled change rather than an
    # immediate one.
    $drivers = @(Get-XenHostDriver | Where-Object { $_.host -eq $xenHost.opaque_ref })
    Write-Host "$($xenHost.name_label) has $($drivers.Count) driver(s)"
    $drivers | Sort-Object name | Select-Object -First 3 | ForEach-Object {
        Write-Host ("  {0,-14} {1,-10} {2} variant(s), active={3}" -f
            $_.name, $_.type, $_.variants.Count, (Get-DriverVariantName $_.active_variant))
    }

    # Select a variant explicitly. It becomes the selected one immediately; whether it is also active
    # depends on whether the hardware is present and the driver already loaded. Host_driver.select
    # refuses a variant whose hardware isn't present (HOST_DRIVER_NO_HARDWARE) - and a host lists
    # drivers for plenty of devices it doesn't have - so pick a driver for hardware this host actually
    # has, and one of its variants that is usable.
    $usable = @($drivers | Sort-Object name | ForEach-Object {
        $driver = $_
        $driver.variants | Where-Object { (Get-XenDriverVariant -Ref $_.opaque_ref).hardware_present } |
            ForEach-Object { [pscustomobject]@{ Driver = $driver; Variant = $_ } }
    })
    if (-not $usable) { throw "no driver on $($xenHost.name_label) has a variant for hardware it has" }
    $target = $usable[0].Driver
    $variant = $usable[0].Variant
    Invoke-XenHostDriver -Ref $target.opaque_ref -XenAction Select -Variant $variant
    $after = Get-XenHostDriver -Ref $target.opaque_ref
    Write-Host "  $($after.name): selected $(Get-DriverVariantName $after.selected_variant), active $(Get-DriverVariantName $after.active_variant)"

    Write-Host "OK: manage-driver-variants"
    $session | Disconnect-XenServer
}

function Get-DriverVariantName {
    <#
    .SYNOPSIS
        A driver variant's name, tolerating the null reference an unloaded driver has.
    #>
    param($VariantRef)
    if (-not $VariantRef -or $VariantRef.opaque_ref -eq "OpaqueRef:NULL") { return "(none)" }
    (Get-XenDriverVariant -Ref $VariantRef.opaque_ref).name
}
```

<details><summary>Example output</summary>

```text
sdk-host1 has 5 driver(s)
  ahci           storage    1 variant(s), active=generic
  bnxt_en        network    1 variant(s), active=generic
  i40e           network    1 variant(s), active=(none)
  ahci: selected generic, active generic
OK: manage-driver-variants
```

</details>

## xe CLI

Source: [`cli/hosts-and-pools/manage-driver-variants.sh`](../../cli/hosts-and-pools/manage-driver-variants.sh)

```bash
# Manage device driver variants.
#
# Inspect a host's device drivers and choose which variant of one to use, seeing the difference between the
# variant that is selected and the one currently loaded.
#
# Run it:
#   ./workflows.sh manage-driver-variants https://xenserver root "$password"

manage_driver_variants() {
    pool=$(first_csv "$(xe pool-list --minimal)")
    host_uuid=$(xe pool-param-get uuid=$pool param-name=master)
    hname=$(xe host-param-get uuid=$host_uuid param-name=name-label)

    drivers=$(xe hostdriver-list host-uuid=$host_uuid --minimal)
    echo "$hname has $(count_csv "$drivers") driver(s)"

    # Sort by name (one xe call per driver to read it, same as the pairs read below) so the printed
    # order and the selection below agree.
    sorted_drivers=$( (for d in $(each_csv "$drivers"); do
        printf '%s\t%s\n' "$(xe hostdriver-param-get uuid=$d param-name=name)" "$d"
    done) | sort | cut -f2)

    # hostdriver-param-get has no "variants-uuid" field (only "variants", a printable name/version
    # summary) - the actual Driver_variant records behind it are found the normal CLI way, with the
    # generic hostdriver-variant-list filtered on driver-uuid=.
    n=0
    for d in $sorted_drivers; do
        n=$((n + 1)); [ "$n" -gt 3 ] && break
        dname=$(xe hostdriver-param-get uuid=$d param-name=name)
        dtype=$(xe hostdriver-param-get uuid=$d param-name=type)
        nvariants=$(count_csv "$(xe hostdriver-variant-list driver-uuid=$d --minimal)")
        active=$(xe hostdriver-param-get uuid=$d param-name=active-variant)
        printf '  %-14s %-10s %d variant(s), active=%s\n' "$dname" "$dtype" "$nvariants" "${active:-(none)}"
    done

    # Select a variant explicitly. It becomes the selected one immediately; whether it is also active
    # depends on whether the hardware is present and the driver already loaded. hostdriver-select on a
    # no-hardware variant raises HOST_DRIVER_NO_HARDWARE - and a host lists drivers for plenty of devices
    # it doesn't have - so pick a driver for hardware this host actually has, and one of its variants
    # that is usable (field "hw-present", not "hardware-present"): the first (driver, variant) pair,
    # across all drivers sorted by name, whose variant reports present.
    driver="" variant=""
    for d in $sorted_drivers; do
        for v in $(each_csv "$(xe hostdriver-variant-list driver-uuid=$d --minimal)"); do
            if [ "$(xe hostdriver-variant-param-get uuid=$v param-name=hw-present)" = "true" ]; then
                driver=$d; variant=$v; break 2
            fi
        done
    done
    if [ -z "$driver" ]; then
        echo "no driver on $hname has a variant for hardware it has" >&2
        return 1
    fi
    dname=$(xe hostdriver-param-get uuid=$driver param-name=name)
    variant_name=$(xe hostdriver-variant-param-get uuid=$variant param-name=name)
    xe hostdriver-select uuid=$driver variant-name="$variant_name"
    selected=$(xe hostdriver-param-get uuid=$driver param-name=selected-variant)
    active=$(xe hostdriver-param-get uuid=$driver param-name=active-variant)
    echo "  $dname: selected ${selected:-(none)}, active ${active:-(none)}"
    echo "OK: manage-driver-variants"
}
```

<details><summary>Example output</summary>

```text
sdk-host1 has 5 driver(s)
  ahci           storage    1 variant(s), active=00000001-0000-0000-4b00-000000000000
  bnxt_en        network    1 variant(s), active=00000001-0000-0000-4500-000000000000
  i40e           network    1 variant(s), active=<not in database>
  ahci: selected 00000001-0000-0000-4b00-000000000000, active 00000001-0000-0000-4b00-000000000000
OK: manage-driver-variants
```

</details>
