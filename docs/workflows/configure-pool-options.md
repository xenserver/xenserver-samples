<!-- Generated from workflows.json, the example sources and a run of each example. Edit those, not this file. -->

# Configure pool options

Read and change the pool-wide options that govern how it behaves — live patching, IGMP snooping and memory-migration compression — then put them back.

Workflow `configure-pool-options`. [All workflows](README.md) · [Connecting](connecting.md)

## C# (.NET)

Source: [`csharp/HostsAndPools/ConfigurePoolOptions.cs`](../../csharp/HostsAndPools/ConfigurePoolOptions.cs)

```csharp
/// <summary>
/// Read and change the pool-wide options that govern how it behaves — live patching, IGMP snooping and
/// memory-migration compression — then put them back.
/// </summary>
/// <example>
/// <code>
/// Workflows.ConfigurePoolOptions("https://xenserver", "root", password);
/// </code>
/// </example>
public static void ConfigurePoolOptions(string url, string user, string password)
{
    var session = Connect(url, user, password);
    var pool = Pool.get_all(session)[0].opaque_ref;

    // None of these is a wizard: they are plain pool settings that a client exposes on a
    // properties page, and each is a single field. Read them, change them, put them back.
    var livePatchingDisabled = Pool.get_live_patching_disabled(session, pool);
    var igmpSnooping = Pool.get_igmp_snooping_enabled(session, pool);
    var migrationCompression = Pool.get_migration_compression(session, pool);
    Console.WriteLine($"  {"live patching disabled",-22} {livePatchingDisabled}");
    Console.WriteLine($"  {"IGMP snooping",-22} {igmpSnooping}");
    Console.WriteLine($"  {"migration compression",-22} {migrationCompression}");

    // Live patching applies host updates without a reboot; disabling it forces the reboot.
    Pool.set_live_patching_disabled(session, pool, !livePatchingDisabled);
    // IGMP snooping keeps multicast off ports that did not ask for it.
    Pool.set_igmp_snooping_enabled(session, pool, !igmpSnooping);
    // Compression trades CPU for bandwidth when a VM's memory is moved between hosts.
    Pool.set_migration_compression(session, pool, !migrationCompression);

    Console.WriteLine("after changing:");
    Console.WriteLine($"  {"live patching disabled",-22} {Pool.get_live_patching_disabled(session, pool)}");
    Console.WriteLine($"  {"IGMP snooping",-22} {Pool.get_igmp_snooping_enabled(session, pool)}");
    Console.WriteLine($"  {"migration compression",-22} {Pool.get_migration_compression(session, pool)}");

    Pool.set_live_patching_disabled(session, pool, livePatchingDisabled);
    Pool.set_igmp_snooping_enabled(session, pool, igmpSnooping);
    Pool.set_migration_compression(session, pool, migrationCompression);
    Console.WriteLine("  restored");
    Console.WriteLine("OK: configure-pool-options");
    session.logout();
}
```

<details><summary>Example output</summary>

```text
  live patching disabled False
  IGMP snooping          False
  migration compression  False
after changing:
  live patching disabled True
  IGMP snooping          True
  migration compression  True
  restored
OK: configure-pool-options
```

</details>

## Python

Source: [`python/hosts_and_pools/configure_pool_options.py`](../../python/hosts_and_pools/configure_pool_options.py)

```python
"""Configure pool options.

Read and change the pool-wide options that govern how it behaves — live patching, IGMP snooping and
memory-migration compression — then put them back.

Run it::

    configure_pool_options("https://xenserver", "root", password)
"""

from connection import connect


def configure_pool_options(url, username, password):
    """Read and change the pool-wide options that govern how the pool behaves.

    None of these is a wizard: they are plain pool settings that a client exposes on a
    properties page, and each is a single field. Read them, change them, put them back."""
    session = connect(url, username, password)
    x = session.xenapi
    pool = x.pool.get_all()[0]

    before = {
        "live patching disabled": x.pool.get_live_patching_disabled(pool),
        "IGMP snooping":          x.pool.get_igmp_snooping_enabled(pool),
        "migration compression":  x.pool.get_migration_compression(pool),
    }
    for name, value in before.items():
        print("  %-22s %s" % (name, value))

    # Live patching applies host updates without a reboot; disabling it forces the reboot.
    x.pool.set_live_patching_disabled(pool, not before["live patching disabled"])
    # IGMP snooping keeps multicast off ports that did not ask for it.
    x.pool.set_igmp_snooping_enabled(pool, not before["IGMP snooping"])
    # Compression trades CPU for bandwidth when a VM's memory is moved between hosts.
    x.pool.set_migration_compression(pool, not before["migration compression"])

    print("after changing:")
    print("  %-22s %s" % ("live patching disabled", x.pool.get_live_patching_disabled(pool)))
    print("  %-22s %s" % ("IGMP snooping", x.pool.get_igmp_snooping_enabled(pool)))
    print("  %-22s %s" % ("migration compression", x.pool.get_migration_compression(pool)))

    x.pool.set_live_patching_disabled(pool, before["live patching disabled"])
    x.pool.set_igmp_snooping_enabled(pool, before["IGMP snooping"])
    x.pool.set_migration_compression(pool, before["migration compression"])
    print("  restored")
    print("OK: configure-pool-options")
    session.logout()
```

<details><summary>Example output</summary>

```text
  live patching disabled False
  IGMP snooping          False
  migration compression  False
after changing:
  live patching disabled True
  IGMP snooping          True
  migration compression  True
  restored
OK: configure-pool-options
```

</details>

## Java

Source: [`java/src/main/java/com/xenserver/samples/hostsandpools/ConfigurePoolOptions.java`](../../java/src/main/java/com/xenserver/samples/hostsandpools/ConfigurePoolOptions.java)

```java
package com.xenserver.samples.hostsandpools;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.Pool;
import com.xensource.xenapi.Session;

import static com.xenserver.samples.PoolConnection.connect;

public final class ConfigurePoolOptions {
    private ConfigurePoolOptions() {
    }

    /**
     * Configure pool options.
     *
     * <p>Read and change the pool-wide options that govern how it behaves — live patching, IGMP snooping
     * and memory-migration compression — then put them back.
     *
     * <p>Run it:
     *
     * <pre>{@code
     * ConfigurePoolOptions.run("https://xenserver", "root", password);
     * }</pre>
     */
    public static void run(String url, String user, String password) throws Exception {
        Connection conn = connect(url, user, password);
        try {
            // None of these is a wizard: they are plain pool settings that a client exposes on a
            // properties page, and each is a single field. Read them, change them, put them back.
            Pool pool = Pool.getAll(conn).iterator().next();

            boolean beforeLivePatching = pool.getLivePatchingDisabled(conn);
            boolean beforeIgmp = pool.getIgmpSnoopingEnabled(conn);
            boolean beforeMigrationCompression = pool.getMigrationCompression(conn);
            System.out.printf("  %-22s %s%n", "live patching disabled", beforeLivePatching);
            System.out.printf("  %-22s %s%n", "IGMP snooping", beforeIgmp);
            System.out.printf("  %-22s %s%n", "migration compression", beforeMigrationCompression);

            // Live patching applies host updates without a reboot; disabling it forces the reboot.
            pool.setLivePatchingDisabled(conn, !beforeLivePatching);
            // IGMP snooping keeps multicast off ports that did not ask for it.
            pool.setIgmpSnoopingEnabled(conn, !beforeIgmp);
            // Compression trades CPU for bandwidth when a VM's memory is moved between hosts.
            pool.setMigrationCompression(conn, !beforeMigrationCompression);

            System.out.println("after changing:");
            System.out.printf("  %-22s %s%n", "live patching disabled", pool.getLivePatchingDisabled(conn));
            System.out.printf("  %-22s %s%n", "IGMP snooping", pool.getIgmpSnoopingEnabled(conn));
            System.out.printf("  %-22s %s%n", "migration compression", pool.getMigrationCompression(conn));

            pool.setLivePatchingDisabled(conn, beforeLivePatching);
            pool.setIgmpSnoopingEnabled(conn, beforeIgmp);
            pool.setMigrationCompression(conn, beforeMigrationCompression);
            System.out.println("  restored");
            System.out.println("OK: configure-pool-options");
        } finally {
            Session.logout(conn);
        }
    }
}
```

<details><summary>Example output</summary>

```text
  live patching disabled false
  IGMP snooping          false
  migration compression  false
after changing:
  live patching disabled true
  IGMP snooping          true
  migration compression  true
  restored
OK: configure-pool-options
```

</details>

## Go

Source: [`go/configure_pool_options.go`](../../go/configure_pool_options.go)

```go
package main

import (
	"fmt"

	"go/xenapi"
)

// configurePoolOptions - Configure pool options.
//
// Read and change the pool-wide options that govern how it behaves — live patching, IGMP snooping
// and memory-migration compression — then put them back.
//
// Run it:
//
//	configurePoolOptions("https://xenserver", "root", password)
func configurePoolOptions(url, user, password string) {
	session := connect(url, user, password)
	defer session.Logout()

	pools, err := xenapi.Pool.GetAll(session)
	check(err)
	pool := pools[0]

	// None of these is a wizard: they are plain pool settings that a client exposes on a properties
	// page, and each is a single field. Read them, change them, put them back.
	livePatching, err := xenapi.Pool.GetLivePatchingDisabled(session, pool)
	check(err)
	igmp, err := xenapi.Pool.GetIgmpSnoopingEnabled(session, pool)
	check(err)
	migrationCompression, err := xenapi.Pool.GetMigrationCompression(session, pool)
	check(err)
	fmt.Printf("  %-22s %t\n", "live patching disabled", livePatching)
	fmt.Printf("  %-22s %t\n", "IGMP snooping", igmp)
	fmt.Printf("  %-22s %t\n", "migration compression", migrationCompression)

	// Live patching applies host updates without a reboot; disabling it forces the reboot.
	check(xenapi.Pool.SetLivePatchingDisabled(session, pool, !livePatching))
	// IGMP snooping keeps multicast off ports that did not ask for it.
	check(xenapi.Pool.SetIgmpSnoopingEnabled(session, pool, !igmp))
	// Compression trades CPU for bandwidth when a VM's memory is moved between hosts.
	check(xenapi.Pool.SetMigrationCompression(session, pool, !migrationCompression))

	fmt.Println("after changing:")
	after1, _ := xenapi.Pool.GetLivePatchingDisabled(session, pool)
	after2, _ := xenapi.Pool.GetIgmpSnoopingEnabled(session, pool)
	after3, _ := xenapi.Pool.GetMigrationCompression(session, pool)
	fmt.Printf("  %-22s %t\n", "live patching disabled", after1)
	fmt.Printf("  %-22s %t\n", "IGMP snooping", after2)
	fmt.Printf("  %-22s %t\n", "migration compression", after3)

	check(xenapi.Pool.SetLivePatchingDisabled(session, pool, livePatching))
	check(xenapi.Pool.SetIgmpSnoopingEnabled(session, pool, igmp))
	check(xenapi.Pool.SetMigrationCompression(session, pool, migrationCompression))
	fmt.Println("  restored")
	fmt.Println("OK: configure-pool-options")
}
```

<details><summary>Example output</summary>

```text
  live patching disabled false
  IGMP snooping          false
  migration compression  false
after changing:
  live patching disabled true
  IGMP snooping          true
  migration compression  true
  restored
OK: configure-pool-options
```

</details>

## PowerShell

Source: [`powershell/HostsAndPools/Invoke-ConfigurePoolOptions.ps1`](../../powershell/HostsAndPools/Invoke-ConfigurePoolOptions.ps1)

```powershell
function Invoke-ConfigurePoolOptions {
    <#
    .SYNOPSIS
        Configure pool options.
    .DESCRIPTION
        Read and change the pool-wide options that govern how it behaves — live patching, IGMP snooping and
        memory-migration compression — then put them back.
    .EXAMPLE
        Invoke-ConfigurePoolOptions -Url https://xenserver -UserName root -Password $password
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password
    )
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password
    $pool = Get-XenPool | Select-Object -First 1

    # None of these is a wizard: they are plain pool settings that a client exposes on a properties
    # page, and each is a single field. Read them, change them, put them back.
    $before = [ordered]@{
        "live patching disabled" = $pool.live_patching_disabled
        "IGMP snooping"          = $pool.igmp_snooping_enabled
        "migration compression"  = $pool.migration_compression
    }
    foreach ($k in $before.Keys) { Write-Host ("  {0,-22} {1}" -f $k, $before[$k]) }

    # Live patching applies host updates without a reboot; disabling it forces the reboot.
    $pool | Set-XenPool -LivePatchingDisabled (-not $before["live patching disabled"])
    # IGMP snooping keeps multicast off ports that did not ask for it.
    $pool | Set-XenPool -IgmpSnoopingEnabled (-not $before["IGMP snooping"])
    # Compression trades CPU for bandwidth when a VM's memory is moved between hosts.
    $pool | Set-XenPool -MigrationCompression (-not $before["migration compression"])

    $after = Get-XenPool -Ref $pool.opaque_ref
    Write-Host "after changing:"
    Write-Host ("  {0,-22} {1}" -f "live patching disabled", $after.live_patching_disabled)
    Write-Host ("  {0,-22} {1}" -f "IGMP snooping", $after.igmp_snooping_enabled)
    Write-Host ("  {0,-22} {1}" -f "migration compression", $after.migration_compression)

    $pool | Set-XenPool -LivePatchingDisabled $before["live patching disabled"]
    $pool | Set-XenPool -IgmpSnoopingEnabled $before["IGMP snooping"]
    $pool | Set-XenPool -MigrationCompression $before["migration compression"]
    Write-Host "  restored"
    Write-Host "OK: configure-pool-options"
    $session | Disconnect-XenServer
}
```

<details><summary>Example output</summary>

```text
  live patching disabled False
  IGMP snooping          False
  migration compression  False
after changing:
  live patching disabled True
  IGMP snooping          True
  migration compression  True
  restored
OK: configure-pool-options
```

</details>

## xe CLI

Source: [`cli/hosts-and-pools/configure-pool-options.sh`](../../cli/hosts-and-pools/configure-pool-options.sh)

```bash
# Configure pool options.
#
# Read and change the pool-wide options that govern how it behaves — live patching, IGMP snooping and
# memory-migration compression — then put them back.
#
# Run it:
#   ./workflows.sh configure-pool-options https://xenserver root "$password"

configure_pool_options() {
    pool=$(first_csv "$(xe pool-list --minimal)")
    live_patching=$(xe pool-param-get uuid=$pool param-name=live-patching-disabled)
    igmp=$(xe pool-param-get uuid=$pool param-name=igmp-snooping-enabled)
    migration_compression=$(xe pool-param-get uuid=$pool param-name=migration-compression)
    printf '  %-22s %s\n' "live patching disabled" "$live_patching"
    printf '  %-22s %s\n' "IGMP snooping" "$igmp"
    printf '  %-22s %s\n' "migration compression" "$migration_compression"

    # Live patching applies host updates without a reboot; disabling it forces the reboot.
    xe pool-param-set uuid=$pool live-patching-disabled=$(negate "$live_patching")
    # IGMP snooping keeps multicast off ports that did not ask for it.
    xe pool-param-set uuid=$pool igmp-snooping-enabled=$(negate "$igmp")
    # Compression trades CPU for bandwidth when a VM's memory is moved between hosts.
    xe pool-param-set uuid=$pool migration-compression=$(negate "$migration_compression")

    echo "after changing:"
    printf '  %-22s %s\n' "live patching disabled" "$(xe pool-param-get uuid=$pool param-name=live-patching-disabled)"
    printf '  %-22s %s\n' "IGMP snooping" "$(xe pool-param-get uuid=$pool param-name=igmp-snooping-enabled)"
    printf '  %-22s %s\n' "migration compression" "$(xe pool-param-get uuid=$pool param-name=migration-compression)"

    xe pool-param-set uuid=$pool live-patching-disabled=$live_patching
    xe pool-param-set uuid=$pool igmp-snooping-enabled=$igmp
    xe pool-param-set uuid=$pool migration-compression=$migration_compression
    echo "  restored"
    echo "OK: configure-pool-options"
}

# The opposite of a "true"/"false" string, for toggling a boolean field and restoring it.
negate() { [ "$1" = "true" ] && echo false || echo true; }
```

<details><summary>Example output</summary>

```text
  live patching disabled false
  IGMP snooping          false
  migration compression  false
after changing:
  live patching disabled true
  IGMP snooping          true
  migration compression  true
  restored
OK: configure-pool-options
```

</details>
