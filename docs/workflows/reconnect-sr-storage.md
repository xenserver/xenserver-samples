<!-- Generated from workflows.json, the example sources and a run of each example. Edit those, not this file. -->

# Point an SR at moved storage

When the storage behind an SR moves to a new address, point the SR at it: a host's connection to an SR cannot be edited, so unplug each one, recreate it with the new settings and plug it back.

Workflow `reconnect-sr-storage`. [All workflows](README.md) · [Connecting](connecting.md)

## PowerShell

Source: [`powershell/Storage/Invoke-ReconnectSrStorage.ps1`](../../powershell/Storage/Invoke-ReconnectSrStorage.ps1)

```powershell
function Invoke-ReconnectSrStorage {
    <#
    .SYNOPSIS
        Point an SR at moved storage.
    .DESCRIPTION
        When the storage behind an SR moves to a new address, point the SR at it: a host's connection to an
        SR cannot be edited, so unplug each one, recreate it with the new settings and plug it back.

        Each host reaches an SR through a PBD, whose device_config (server, path, target, ...) says where
        the storage is. A PBD's device_config is fixed when it is created, so changing it means unplugging
        the PBD, destroying it, and creating and plugging a new one with the updated settings, host by host.
        The SR and its disks are untouched throughout. Every PBD has to be unplugged first, which needs every
        VM using the SR to be shut down. This example creates an NFS SR on NfsServer:NfsPath to work on, and
        forgets it again at the end; NewNfsServer defaults to NfsServer, which reconnects the SR to the same
        storage.
    .EXAMPLE
        Invoke-ReconnectSrStorage -Url https://xenserver -UserName root -Password $password -NfsServer 192.0.2.10 -NfsPath /export/spare -NewNfsServer 192.0.2.11
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password,
        [string]$NfsServer = "192.0.2.10",
        [string]$NfsPath = "/export/spare",
        [string]$NewNfsServer
    )
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password
    if (-not $NewNfsServer) { $NewNfsServer = $NfsServer }

    $xenHost = Get-XenHost | Select-Object -First 1
    $sr = New-XenSR -XenHost $xenHost -PhysicalSize 0 `
        -DeviceConfig @{ server = $NfsServer; serverpath = $NfsPath; nfsversion = "3" } `
        -NameLabel "sdk-example-moved-storage" -NameDescription "SR used by the SDK reconnect example" `
        -Type "nfs" -ContentType "user" -Shared $true -PassThru
    try {
        $pbds = @($sr.PBDs | ForEach-Object { Get-XenPBD -Ref $_ })
        $pbds | Invoke-XenPBD -XenAction Unplug

        foreach ($pbd in $pbds) {
            $deviceConfig = @{} + $pbd.device_config
            $deviceConfig.server = $NewNfsServer
            Remove-XenPBD -Ref $pbd
            $replacement = New-XenPBD -XenHost $pbd.host -SR $sr -DeviceConfig $deviceConfig -OtherConfig @{} -PassThru
            $replacement | Invoke-XenPBD -XenAction Plug
            Write-Host ("{0}: now reaches {1}:{2}" -f
                (Get-XenHost -Ref $pbd.host).name_label, $deviceConfig.server, $deviceConfig.serverpath)
        }
    }
    finally {
        # Tidy up: detach the SR from every host and forget it, leaving the storage itself untouched.
        Invoke-DetachAndForgetSr -Ref $sr
    }
    Write-Host "OK: reconnect-sr-storage"
    $session | Disconnect-XenServer
}
```

<details><summary>Example output</summary>

```text
sdk-host1: now reaches 192.0.2.10:/export/spare
sdk-host2: now reaches 192.0.2.10:/export/spare
OK: reconnect-sr-storage
```

</details>

## xe CLI

Source: [`cli/storage/reconnect-sr-storage.sh`](../../cli/storage/reconnect-sr-storage.sh)

```bash
# Point an SR at moved storage.
#
# When the storage behind an SR moves to a new address, point the SR at it: a host's connection to an SR
# cannot be edited, so unplug each one, recreate it with the new settings and plug it back.
#
# Run it:
#   ./workflows.sh reconnect-sr-storage https://xenserver root "$password"
#
# Optional key=value arguments (default):
#   nfs_server (192.0.2.10)
#   nfs_path (/export/spare)
#   new_nfs_server (nfs_server)

# Each host reaches an SR through a PBD, whose device-config (server, path, target, ...) says where the
# storage is. A PBD's device-config is fixed when it is created, so changing it means unplugging the PBD,
# destroying it, and creating and plugging a new one with the updated settings, host by host. The SR and
# its disks are untouched throughout. Every PBD has to be unplugged first, which needs every VM using the
# SR to be shut down. This example creates an NFS SR to work on, and forgets it again at the end.
reconnect_sr_storage() {
    local nfs_server nfs_path new_server sr pbd pbd_host path pbds
    nfs_server=$(param nfs_server "192.0.2.10")
    nfs_path=$(param nfs_path "/export/spare")
    new_server=$(param new_nfs_server "$nfs_server")

    sr=$(xe sr-create host-uuid=$(first_host) type=nfs shared=true content-type=user \
        name-label=sdk-example-moved-storage device-config:server="$nfs_server" \
        device-config:serverpath="$nfs_path" device-config:nfsversion=3)
    pbds=$(xe pbd-list sr-uuid=$sr --minimal)
    for pbd in $(each_csv "$pbds"); do
        xe pbd-unplug uuid=$pbd
    done

    for pbd in $(each_csv "$pbds"); do
        # Not "host": that is where xe sends its commands (connection.sh).
        pbd_host=$(xe pbd-param-get uuid=$pbd param-name=host-uuid)
        path=$(xe pbd-param-get uuid=$pbd param-name=device-config param-key=serverpath)
        xe pbd-destroy uuid=$pbd
        pbd=$(xe pbd-create host-uuid=$pbd_host sr-uuid=$sr device-config:server="$new_server" \
            device-config:serverpath="$path" device-config:nfsversion=3)
        xe pbd-plug uuid=$pbd
        echo "$(xe host-param-get uuid=$pbd_host param-name=name-label): now reaches $new_server:$path"
    done

    # Tidy up: detach the SR from every host and forget it, leaving the storage itself untouched.
    detach_and_forget_sr $sr
    echo "OK: reconnect-sr-storage"
}
```

<details><summary>Example output</summary>

```text
sdk-host1: now reaches 192.0.2.10:/export/spare
sdk-host2: now reaches 192.0.2.10:/export/spare
OK: reconnect-sr-storage
```

</details>

## Python

Source: [`python/storage/reconnect_sr_storage.py`](../../python/storage/reconnect_sr_storage.py)

```python
"""Point an SR at moved storage.

When the storage behind an SR moves to a new address, point the SR at it: a host's connection to an SR
cannot be edited, so unplug each one, recreate it with the new settings and plug it back.

Run it::

    reconnect_sr_storage("https://xenserver", "root", password, "192.0.2.10", "/export/spare",
                         new_nfs_server="192.0.2.11")
"""

from connection import connect


def reconnect_sr_storage(url, username, password, nfs_server="192.0.2.10", nfs_path="/export/spare",
                         new_nfs_server=None):
    """Create an NFS SR on nfs_server:nfs_path, re-point it at new_nfs_server, then forget it.

    Each host reaches an SR through a PBD, whose device_config (server, path, target, ...) says where
    the storage is. A PBD's device_config is fixed when it is created, so changing it means unplugging
    the PBD, destroying it, and creating and plugging a new one with the updated settings, host by host.
    The SR and its disks are untouched throughout. Every PBD has to be unplugged first, which needs
    every VM using the SR to be shut down. new_nfs_server defaults to nfs_server, which reconnects
    the SR to the same storage."""
    session = connect(url, username, password)
    x = session.xenapi
    new_nfs_server = new_nfs_server or nfs_server

    host = x.host.get_all()[0]
    sr = x.SR.create(host, {"server": nfs_server, "serverpath": nfs_path, "nfsversion": "3"},
                     "0", "sdk-example-moved-storage", "SR used by the SDK reconnect example",
                     "nfs", "user", True, {})
    try:
        pbds = x.SR.get_PBDs(sr)
        for pbd in pbds:
            x.PBD.unplug(pbd)

        for pbd in pbds:
            record = x.PBD.get_record(pbd)
            device_config = dict(record["device_config"], server=new_nfs_server)
            x.PBD.destroy(pbd)
            pbd = x.PBD.create({"host": record["host"], "SR": sr, "device_config": device_config,
                                "other_config": {}})
            x.PBD.plug(pbd)
            print("%s: now reaches %s:%s" % (x.host.get_name_label(record["host"]),
                                             device_config["server"], device_config["serverpath"]))
    finally:
        # Tidy up: detach the SR from every host and forget it, leaving the storage itself untouched.
        for pbd in x.SR.get_PBDs(sr):
            if x.PBD.get_currently_attached(pbd):
                x.PBD.unplug(pbd)
        x.SR.forget(sr)
    print("OK: reconnect-sr-storage")
    session.logout()
```

<details><summary>Example output</summary>

```text
sdk-host1: now reaches 192.0.2.10:/export/spare
sdk-host2: now reaches 192.0.2.10:/export/spare
OK: reconnect-sr-storage
```

</details>

## C# (.NET)

Source: [`csharp/Storage/ReconnectSrStorage.cs`](../../csharp/Storage/ReconnectSrStorage.cs)

```csharp
/// <summary>
/// When the storage behind an SR moves to a new address, point the SR at it: a host's connection to an
/// SR cannot be edited, so unplug each one, recreate it with the new settings and plug it back.
/// </summary>
/// <example>
/// <code>
/// Workflows.ReconnectSrStorage("https://xenserver", "root", password, "192.0.2.10", "/export/spare",
///     "192.0.2.11");
/// </code>
/// </example>
/// <remarks>
/// Each host reaches an SR through a PBD, whose device_config (server, path, target, ...) says where the
/// storage is. A PBD's device_config is fixed when it is created, so changing it means unplugging the
/// PBD, destroying it, and creating and plugging a new one with the updated settings, host by host. The
/// SR and its disks are untouched throughout. Every PBD has to be unplugged first, which needs every VM
/// using the SR to be shut down. This example creates an NFS SR on nfsServer:nfsPath to work on, and
/// forgets it again at the end; newNfsServer defaults to nfsServer, which reconnects the SR to the same
/// storage.
/// </remarks>
public static void ReconnectSrStorage(string url, string user, string password, string nfsServer,
    string nfsPath, string newNfsServer = null)
{
    var session = Connect(url, user, password);
    newNfsServer ??= nfsServer;

    var host = Host.get_all(session).First();
    var sr = SR.create(session, host, new Dictionary<string, string>
    {
        ["server"] = nfsServer,
        ["serverpath"] = nfsPath,
        ["nfsversion"] = "3",
    }, 0, "sdk-example-moved-storage", "SR used by the SDK reconnect example",
        "nfs", "user", true, new Dictionary<string, string>());
    try
    {
        var pbds = SR.get_PBDs(session, sr);
        foreach (var pbd in pbds) PBD.unplug(session, pbd);

        foreach (var pbd in pbds)
        {
            var record = PBD.get_record(session, pbd);
            var deviceConfig = new Dictionary<string, string>(record.device_config) { ["server"] = newNfsServer };
            PBD.destroy(session, pbd);
            var replacement = PBD.create(session, new PBD
            {
                host = record.host,
                SR = sr,
                device_config = deviceConfig,
                other_config = new Dictionary<string, string>(),
            });
            PBD.plug(session, replacement);
            Console.WriteLine($"{Host.get_name_label(session, record.host)}: now reaches "
                              + $"{deviceConfig["server"]}:{deviceConfig["serverpath"]}");
        }
    }
    finally
    {
        // Tidy up: detach the SR from every host and forget it, leaving the storage itself untouched.
        DetachAndForgetSr(session, sr);
    }
    Console.WriteLine("OK: reconnect-sr-storage");
    session.logout();
}
```

<details><summary>Example output</summary>

```text
sdk-host1: now reaches 192.0.2.10:/export/spare
sdk-host2: now reaches 192.0.2.10:/export/spare
OK: reconnect-sr-storage
```

</details>

## Go

Source: [`go/reconnect_sr_storage.go`](../../go/reconnect_sr_storage.go)

```go
package main

import (
	"fmt"

	"go/xenapi"
)

// reconnectSrStorage - Point an SR at moved storage.
//
// When the storage behind an SR moves to a new address, point the SR at it: a host's connection to an
// SR cannot be edited, so unplug each one, recreate it with the new settings and plug it back.
//
// Each host reaches an SR through a PBD, whose device_config (server, path, target, ...) says where
// the storage is. A PBD's device_config is fixed when it is created, so changing it means unplugging
// the PBD, destroying it, and creating and plugging a new one with the updated settings, host by host.
// The SR and its disks are untouched throughout. Every PBD has to be unplugged first, which needs every
// VM using the SR to be shut down. This example creates an NFS SR on nfsServer:nfsPath to work on, and
// forgets it again at the end; an empty newNfsServer reconnects the SR to the same storage.
//
// Run it:
//
//	reconnectSrStorage("https://xenserver", "root", password, "192.0.2.10", "/export/spare", "192.0.2.11")
func reconnectSrStorage(url, user, password, nfsServer, nfsPath, newNfsServer string) {
	session := connect(url, user, password)
	defer session.Logout()
	if newNfsServer == "" {
		newNfsServer = nfsServer
	}

	hosts, err := xenapi.Host.GetAll(session)
	check(err)
	sr, err := xenapi.SR.Create(session, hosts[0], map[string]string{
		"server":     nfsServer,
		"serverpath": nfsPath,
		"nfsversion": "3",
	}, 0, "sdk-example-moved-storage", "SR used by the SDK reconnect example",
		"nfs", "user", true, map[string]string{})
	check(err)
	// Tidy up: detach the SR from every host and forget it, leaving the storage itself untouched.
	defer detachAndForgetSR(session, sr)

	pbds, err := xenapi.SR.GetPBDs(session, sr)
	check(err)
	for _, pbd := range pbds {
		check(xenapi.PBD.Unplug(session, pbd))
	}

	for _, pbd := range pbds {
		record, err := xenapi.PBD.GetRecord(session, pbd)
		check(err)
		deviceConfig := map[string]string{}
		for k, v := range record.DeviceConfig {
			deviceConfig[k] = v
		}
		deviceConfig["server"] = newNfsServer
		check(xenapi.PBD.Destroy(session, pbd))
		replacement, err := xenapi.PBD.Create(session, xenapi.PBDRecord{
			Host:         record.Host,
			SR:           sr,
			DeviceConfig: deviceConfig,
			OtherConfig:  map[string]string{},
		})
		check(err)
		check(xenapi.PBD.Plug(session, replacement))
		name, _ := xenapi.Host.GetNameLabel(session, record.Host)
		fmt.Printf("%s: now reaches %s:%s\n", name, deviceConfig["server"], deviceConfig["serverpath"])
	}
	fmt.Println("OK: reconnect-sr-storage")
}
```

<details><summary>Example output</summary>

```text
sdk-host1: now reaches 192.0.2.10:/export/spare
sdk-host2: now reaches 192.0.2.10:/export/spare
OK: reconnect-sr-storage
```

</details>

## Java

Source: [`java/src/main/java/com/xenserver/samples/storage/ReconnectSrStorage.java`](../../java/src/main/java/com/xenserver/samples/storage/ReconnectSrStorage.java)

```java
package com.xenserver.samples.storage;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.Host;
import com.xensource.xenapi.PBD;
import com.xensource.xenapi.SR;
import com.xensource.xenapi.Session;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import static com.xenserver.samples.Helpers.detachAndForgetSr;
import static com.xenserver.samples.PoolConnection.connect;

public final class ReconnectSrStorage {
    private ReconnectSrStorage() {
    }

    /**
     * Point an SR at moved storage.
     *
     * <p>When the storage behind an SR moves to a new address, point the SR at it: a host's connection to an
     * SR cannot be edited, so unplug each one, recreate it with the new settings and plug it back.
     *
     * <p>Each host reaches an SR through a PBD, whose device_config (server, path, target, ...) says where
     * the storage is. A PBD's device_config is fixed when it is created, so changing it means unplugging the
     * PBD, destroying it, and creating and plugging a new one with the updated settings, host by host. The
     * SR and its disks are untouched throughout. Every PBD has to be unplugged first, which needs every VM
     * using the SR to be shut down. This example creates an NFS SR on nfsServer:nfsPath to work on, and
     * forgets it again at the end; a null newNfsServer reconnects the SR to the same storage.
     *
     * <p>Run it:
     *
     * <pre>{@code
     * ReconnectSrStorage.run("https://xenserver", "root", password, "192.0.2.10", "/export/spare", "192.0.2.11");
     * }</pre>
     */
    public static void run(String url, String user, String password, String nfsServer, String nfsPath,
                           String newNfsServer) throws Exception {
        Connection conn = connect(url, user, password);
        String newServer = newNfsServer != null ? newNfsServer : nfsServer;

        Host host = Host.getAll(conn).iterator().next();
        Map<String, String> deviceConfig = new HashMap<>();
        deviceConfig.put("server", nfsServer);
        deviceConfig.put("serverpath", nfsPath);
        deviceConfig.put("nfsversion", "3");
        SR sr = SR.create(conn, host, deviceConfig, 0L, "sdk-example-moved-storage",
            "SR used by the SDK reconnect example", "nfs", "user", true, new HashMap<>());
        try {
            List<PBD> pbds = new ArrayList<>(sr.getPBDs(conn));
            for (PBD pbd : pbds) pbd.unplug(conn);

            for (PBD pbd : pbds) {
                PBD.Record record = pbd.getRecord(conn);
                Map<String, String> moved = new HashMap<>(record.deviceConfig);
                moved.put("server", newServer);
                pbd.destroy(conn);
                PBD.Record replacement = new PBD.Record();
                replacement.host = record.host;
                replacement.SR = sr;
                replacement.deviceConfig = moved;
                replacement.otherConfig = new HashMap<>();
                PBD.create(conn, replacement).plug(conn);
                System.out.printf("%s: now reaches %s:%s%n", record.host.getNameLabel(conn),
                    moved.get("server"), moved.get("serverpath"));
            }
        } finally {
            // Tidy up: detach the SR from every host and forget it, leaving the storage itself untouched.
            detachAndForgetSr(conn, sr);
        }
        System.out.println("OK: reconnect-sr-storage");
        Session.logout(conn);
    }
}
```

<details><summary>Example output</summary>

```text
sdk-host2: now reaches 192.0.2.10:/export/spare
sdk-host1: now reaches 192.0.2.10:/export/spare
OK: reconnect-sr-storage
```

</details>
