<!-- Generated from workflows.json, the example sources and a run of each example. Edit those, not this file. -->

# Configure host storage

Set a host's iSCSI initiator name and turn on storage multipathing, then restore both.

Workflow `configure-host-storage`. [All workflows](README.md) · [Connecting](connecting.md)

## C# (.NET)

Source: [`csharp/HostsAndPools/ConfigureHostStorage.cs`](../../csharp/HostsAndPools/ConfigureHostStorage.cs)

```csharp
/// <summary>
/// Set a host's iSCSI initiator name and turn on storage multipathing, then restore both.
/// </summary>
/// <example>
/// <code>
/// Workflows.ConfigureHostStorage("https://xenserver", "root", password);
/// </code>
/// </example>
public static void ConfigureHostStorage(string url, string user, string password)
{
    var session = Connect(url, user, password);
    var host = Pool.get_master(session, Pool.get_all(session)[0].opaque_ref).opaque_ref;

    // The IQN identifies this host to iSCSI targets, so a target's access list is written against
    // it — changing it on a host with live iSCSI storage cuts it off. Existing iSCSI SRs must be
    // detached first: changing the IQN underneath them can make the host unable to reconnect to new
    // or existing SRs until the storage target is updated to match. Multipathing uses every path to
    // the storage rather than one, and on real hardware you put the host into maintenance mode
    // before changing it, because the paths are rebuilt.
    var beforeIqn = Host.get_iscsi_iqn(session, host);
    var beforeMultipathing = Host.get_multipathing(session, host);
    Console.WriteLine($"{Host.get_name_label(session, host)}: iSCSI IQN '{beforeIqn}', " +
                      $"multipathing {beforeMultipathing}");

    Host.set_iscsi_iqn(session, host, $"iqn.2026-01.com.example:{Host.get_name_label(session, host)}");
    Host.set_multipathing(session, host, true);
    Console.WriteLine($"  IQN now:      {Host.get_iscsi_iqn(session, host)}");
    Console.WriteLine($"  multipathing: {Host.get_multipathing(session, host)}");

    // set_iscsi_iqn refuses an empty string (INVALID_VALUE); only restore it if this host actually
    // had one set before - a host that has never had an IQN configured has it empty, and there is no
    // way to set it back to empty through this call.
    if (!string.IsNullOrEmpty(beforeIqn)) Host.set_iscsi_iqn(session, host, beforeIqn);
    Host.set_multipathing(session, host, beforeMultipathing);
    Console.WriteLine("  restored");
    Console.WriteLine("OK: configure-host-storage");
    session.logout();
}
```

<details><summary>Example output</summary>

```text
sdk-host1: iSCSI IQN 'iqn.2026-10.com.example:00000001', multipathing False
  IQN now:      iqn.2026-01.com.example:sdk-host1
  multipathing: True
  restored
OK: configure-host-storage
```

</details>

## Python

Source: [`python/hosts_and_pools/configure_host_storage.py`](../../python/hosts_and_pools/configure_host_storage.py)

```python
"""Configure host storage.

Set a host's iSCSI initiator name and turn on storage multipathing, then restore both.

Run it::

    configure_host_storage("https://xenserver", "root", password)
"""

from connection import connect


def configure_host_storage(url, username, password):
    """Set a host's iSCSI initiator name and turn on storage multipathing.

    The IQN identifies this host to iSCSI targets, so a target's access list is written
    against it -- changing it on a host with live iSCSI storage cuts it off. Existing iSCSI SRs
    must be detached first: changing the IQN underneath them can make the host unable to
    reconnect to new or existing SRs until the storage target is updated to match. Multipathing
    uses every path to the storage rather than one, and on real hardware you put the host into
    maintenance mode before changing it, because the paths are rebuilt."""
    session = connect(url, username, password)
    x = session.xenapi
    host = x.pool.get_master(x.pool.get_all()[0])

    before_iqn = x.host.get_iscsi_iqn(host)
    before_multipathing = x.host.get_multipathing(host)
    print("%s: iSCSI IQN %r, multipathing %s"
          % (x.host.get_name_label(host), before_iqn, before_multipathing))

    x.host.set_iscsi_iqn(host, "iqn.2026-01.com.example:%s" % x.host.get_name_label(host))
    x.host.set_multipathing(host, True)
    print("  IQN now:      %s" % x.host.get_iscsi_iqn(host))
    print("  multipathing: %s" % x.host.get_multipathing(host))

    # set_iscsi_iqn refuses an empty string (INVALID_VALUE); only restore it if this host actually
    # had one set before - a host that has never had an IQN configured has it empty, and there is
    # no way to set it back to empty through this call.
    if before_iqn:
        x.host.set_iscsi_iqn(host, before_iqn)
    x.host.set_multipathing(host, before_multipathing)
    print("  restored")
    print("OK: configure-host-storage")
    session.logout()
```

<details><summary>Example output</summary>

```text
sdk-host1: iSCSI IQN 'iqn.2026-10.com.example:00000001', multipathing False
  IQN now:      iqn.2026-01.com.example:sdk-host1
  multipathing: True
  restored
OK: configure-host-storage
```

</details>

## Java

Source: [`java/src/main/java/com/xenserver/samples/hostsandpools/ConfigureHostStorage.java`](../../java/src/main/java/com/xenserver/samples/hostsandpools/ConfigureHostStorage.java)

```java
package com.xenserver.samples.hostsandpools;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.Host;
import com.xensource.xenapi.Pool;
import com.xensource.xenapi.Session;

import static com.xenserver.samples.PoolConnection.connect;

public final class ConfigureHostStorage {
    private ConfigureHostStorage() {
    }

    /**
     * Configure host storage.
     *
     * <p>Set a host's iSCSI initiator name and turn on storage multipathing, then restore both.
     *
     * <p>Run it:
     *
     * <pre>{@code
     * ConfigureHostStorage.run("https://xenserver", "root", password);
     * }</pre>
     */
    public static void run(String url, String user, String password) throws Exception {
        Connection conn = connect(url, user, password);
        try {
            // The IQN identifies this host to iSCSI targets, so a target's access list is written
            // against it - changing it on a host with live iSCSI storage cuts it off. Existing iSCSI
            // SRs must be detached first: changing the IQN underneath them can make the host unable to
            // reconnect to new or existing SRs until the storage target is updated to match. Multipathing
            // uses every path to the storage rather than one, and on real hardware you put the host into
            // maintenance mode before changing it, because the paths are rebuilt.
            Host host = Pool.getAll(conn).iterator().next().getMaster(conn);

            String beforeIqn = host.getIscsiIqn(conn);
            boolean beforeMultipathing = host.getMultipathing(conn);
            System.out.println(host.getNameLabel(conn) + ": iSCSI IQN '" + beforeIqn
                    + "', multipathing " + beforeMultipathing);

            host.setIscsiIqn(conn, "iqn.2026-01.com.example:" + host.getNameLabel(conn));
            host.setMultipathing(conn, true);
            System.out.println("  IQN now:      " + host.getIscsiIqn(conn));
            System.out.println("  multipathing: " + host.getMultipathing(conn));

            // set_iscsi_iqn refuses an empty string (INVALID_VALUE); only restore it if this host actually
            // had one set before - a host that has never had an IQN configured has it empty, and there is
            // no way to set it back to empty through this call.
            if (beforeIqn != null && !beforeIqn.isEmpty()) host.setIscsiIqn(conn, beforeIqn);
            host.setMultipathing(conn, beforeMultipathing);
            System.out.println("  restored");
            System.out.println("OK: configure-host-storage");
        } finally {
            Session.logout(conn);
        }
    }
}
```

<details><summary>Example output</summary>

```text
sdk-host1: iSCSI IQN 'iqn.2026-10.com.example:00000001', multipathing false
  IQN now:      iqn.2026-01.com.example:sdk-host1
  multipathing: true
  restored
OK: configure-host-storage
```

</details>

## Go

Source: [`go/configure_host_storage.go`](../../go/configure_host_storage.go)

```go
package main

import (
	"fmt"

	"go/xenapi"
)

// configureHostStorage - Configure host storage.
//
// Set a host's iSCSI initiator name and turn on storage multipathing, then restore both.
//
// The IQN identifies this host to iSCSI targets, so a target's access list is written against it -
// changing it on a host with live iSCSI storage cuts it off. Existing iSCSI SRs must be detached
// first: changing the IQN underneath them can make the host unable to reconnect to new or existing
// SRs until the storage target is updated to match. Multipathing uses every path to the storage
// rather than one, and on real hardware you put the host into maintenance mode before changing it,
// because the paths are rebuilt.
//
// Run it:
//
//	configureHostStorage("https://xenserver", "root", password)
func configureHostStorage(url, user, password string) {
	session := connect(url, user, password)
	defer session.Logout()

	pools, err := xenapi.Pool.GetAll(session)
	check(err)
	host, err := xenapi.Pool.GetMaster(session, pools[0])
	check(err)
	hostName, err := xenapi.Host.GetNameLabel(session, host)
	check(err)

	beforeIqn, err := xenapi.Host.GetIscsiIqn(session, host)
	check(err)
	beforeMultipathing, err := xenapi.Host.GetMultipathing(session, host)
	check(err)
	fmt.Printf("%s: iSCSI IQN %q, multipathing %t\n", hostName, beforeIqn, beforeMultipathing)

	check(xenapi.Host.SetIscsiIqn(session, host, "iqn.2026-01.com.example:"+hostName))
	check(xenapi.Host.SetMultipathing(session, host, true))
	iqn, _ := xenapi.Host.GetIscsiIqn(session, host)
	multipathing, _ := xenapi.Host.GetMultipathing(session, host)
	fmt.Printf("  IQN now:      %s\n", iqn)
	fmt.Printf("  multipathing: %t\n", multipathing)

	// set_iscsi_iqn refuses an empty string (INVALID_VALUE) - only restore it if this host actually
	// had one set before; a host that has never had an IQN configured can't be "restored" to empty.
	if beforeIqn != "" {
		check(xenapi.Host.SetIscsiIqn(session, host, beforeIqn))
	}
	check(xenapi.Host.SetMultipathing(session, host, beforeMultipathing))
	fmt.Println("  restored")
	fmt.Println("OK: configure-host-storage")
}
```

<details><summary>Example output</summary>

```text
sdk-host1: iSCSI IQN "iqn.2026-10.com.example:00000001", multipathing false
  IQN now:      iqn.2026-01.com.example:sdk-host1
  multipathing: true
  restored
OK: configure-host-storage
```

</details>

## PowerShell

Source: [`powershell/HostsAndPools/Invoke-ConfigureHostStorage.ps1`](../../powershell/HostsAndPools/Invoke-ConfigureHostStorage.ps1)

```powershell
function Invoke-ConfigureHostStorage {
    <#
    .SYNOPSIS
        Configure host storage.
    .DESCRIPTION
        Set a host's iSCSI initiator name and turn on storage multipathing, then restore both.
    .EXAMPLE
        Invoke-ConfigureHostStorage -Url https://xenserver -UserName root -Password $password
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password
    )
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password
    $xenHost = Get-XenHost -Ref (Get-XenPool | Select-Object -First 1).master.opaque_ref

    # The IQN identifies this host to iSCSI targets, so a target's access list is written against it -
    # changing it on a host with live iSCSI storage cuts it off. Existing iSCSI SRs must be detached
    # first: changing the IQN underneath them can make the host unable to reconnect to new or existing
    # SRs until the storage target is updated to match. Multipathing uses every path to the storage
    # rather than one, and on real hardware you put the host into maintenance mode before changing it,
    # because the paths are rebuilt.
    $beforeIqn = $xenHost.iscsi_iqn
    $beforeMultipathing = $xenHost.multipathing
    Write-Host "$($xenHost.name_label): iSCSI IQN '$beforeIqn', multipathing $beforeMultipathing"

    $xenHost | Set-XenHost -IscsiIqn "iqn.2026-01.com.example:$($xenHost.name_label)"
    $xenHost | Set-XenHost -Multipathing $true
    $updated = Get-XenHost -Ref $xenHost.opaque_ref
    Write-Host "  IQN now:      $($updated.iscsi_iqn)"
    Write-Host "  multipathing: $($updated.multipathing)"

    # set_iscsi_iqn refuses an empty string (INVALID_VALUE); only restore it if this host actually had
    # one set before - a host that has never had an IQN configured has it empty, and there is no way to
    # set it back to empty through this call.
    if ($beforeIqn) { $xenHost | Set-XenHost -IscsiIqn $beforeIqn }
    $xenHost | Set-XenHost -Multipathing $beforeMultipathing
    Write-Host "  restored"
    Write-Host "OK: configure-host-storage"
    $session | Disconnect-XenServer
}
```

<details><summary>Example output</summary>

```text
sdk-host1: iSCSI IQN 'iqn.2026-10.com.example:00000001', multipathing False
  IQN now:      iqn.2026-01.com.example:sdk-host1
  multipathing: True
  restored
OK: configure-host-storage
```

</details>

## xe CLI

Source: [`cli/hosts-and-pools/configure-host-storage.sh`](../../cli/hosts-and-pools/configure-host-storage.sh)

```bash
# Configure host storage.
#
# Set a host's iSCSI initiator name and turn on storage multipathing, then restore both.
#
# Run it:
#   ./workflows.sh configure-host-storage https://xenserver root "$password"

configure_host_storage() {
    pool=$(first_csv "$(xe pool-list --minimal)")
    host_uuid=$(xe pool-param-get uuid=$pool param-name=master)
    hname=$(xe host-param-get uuid=$host_uuid param-name=name-label)

    # Existing iSCSI SRs must be detached first: changing the IQN underneath them can make the host
    # unable to reconnect to new or existing SRs until the storage target is updated to match.
    before_iqn=$(xe host-param-get uuid=$host_uuid param-name=iscsi_iqn)
    before_multipathing=$(xe host-param-get uuid=$host_uuid param-name=multipathing)
    echo "$hname: iSCSI IQN '$before_iqn', multipathing $before_multipathing"

    xe host-param-set uuid=$host_uuid iscsi_iqn="iqn.2026-01.com.example:$hname"
    xe host-param-set uuid=$host_uuid multipathing=true
    echo "  IQN now:      $(xe host-param-get uuid=$host_uuid param-name=iscsi_iqn)"
    echo "  multipathing: $(xe host-param-get uuid=$host_uuid param-name=multipathing)"

    # host-param-set refuses an empty iscsi_iqn (INVALID_VALUE) - only restore it if this host actually had
    # one set before; a host that never had an IQN configured can't be "restored" to empty.
    [ -n "$before_iqn" ] && xe host-param-set uuid=$host_uuid iscsi_iqn="$before_iqn"
    xe host-param-set uuid=$host_uuid multipathing=$before_multipathing
    echo "  restored"
    echo "OK: configure-host-storage"
}
```

<details><summary>Example output</summary>

```text
sdk-host1: iSCSI IQN 'iqn.2026-10.com.example:00000001', multipathing false
  IQN now:      iqn.2026-01.com.example:sdk-host1
  multipathing: true
  restored
OK: configure-host-storage
```

</details>
