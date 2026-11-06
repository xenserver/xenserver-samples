<!-- Generated from workflows.json, the example sources and a run of each example. Edit those, not this file. -->

# Set the pool's default storage

Choose where the pool puts new disks, suspended VMs' memory images and host crash dumps by default, then put the original choice back.

Workflow `set-default-sr`. [All workflows](README.md) · [Connecting](connecting.md)

## PowerShell

Source: [`powershell/Storage/Invoke-SetDefaultSr.ps1`](../../powershell/Storage/Invoke-SetDefaultSr.ps1)

```powershell
function Invoke-SetDefaultSr {
    <#
    .SYNOPSIS
        Set the pool's default storage.
    .DESCRIPTION
        Choose where the pool puts new disks, suspended VMs' memory images and host crash dumps by default,
        then put the original choice back.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password,
        [string]$NfsServer = "192.0.2.10",
        [string]$NfsPath = "/export/spare"
    )
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password
    $pool = Get-XenPool | Select-Object -First 1

    # Capture all three separately. New disks land on the default SR, a suspended VM's memory image goes
    # to the suspend-image SR and host crash dumps to the crash-dump SR. They are usually the same
    # storage but need not be, and a pool that has never suspended or crashed anything can legitimately
    # leave the latter two unset - so restoring all three from the default would quietly invent settings
    # that were not there. The record already holds each as a reference, so it can be handed straight
    # back to Set-XenPool later.
    $before = $pool.default_SR
    $beforeSuspend = $pool.suspend_image_SR
    $beforeCrash = $pool.crash_dump_SR
    Write-Host ("default storage:  {0}" -f (Get-SrLabel $before))
    Write-Host ("  suspend images: {0}" -f (Get-SrLabel $beforeSuspend))
    Write-Host ("  crash dumps:    {0}" -f (Get-SrLabel $beforeCrash))

    # Somewhere to switch to. A pool default has to be reachable from every host, so it is a shared SR;
    # a local one would strand any VM whose disk landed on the wrong host.
    $sr = New-XenSR -XenHost (Get-XenHost | Select-Object -First 1) -PhysicalSize 0 `
        -DeviceConfig @{ server = $NfsServer; serverpath = $NfsPath; nfsversion = "3" } `
        -NameLabel "sdk-example-default" -NameDescription "SR used by the SDK default-storage example" `
        -Type "nfs" -ContentType "user" -Shared $true -PassThru

    $srRef = $sr | ConvertTo-XenRef
    $pool | Set-XenPool -DefaultSR $srRef -SuspendImageSR $srRef -CrashDumpSR $srRef
    Write-Host ("  switched to:    {0}" -f (Get-SrLabel (Get-XenPool -Ref $pool.opaque_ref).default_SR))

    # Restore the original choice before tidying up: an SR that is still the pool default is the awkward
    # one to remove.
    $pool | Set-XenPool -DefaultSR $before -SuspendImageSR $beforeSuspend -CrashDumpSR $beforeCrash
    @($sr.PBDs | ForEach-Object { Get-XenPBD -Ref $_.opaque_ref }) | Invoke-XenPBD -XenAction Unplug
    $sr | Invoke-XenSR -XenAction Forget
    Write-Host ("  restored to:    {0}" -f (Get-SrLabel (Get-XenPool -Ref $pool.opaque_ref).default_SR))
    Write-Host "OK: set-default-sr"
    $session | Disconnect-XenServer
}

function Get-SrLabel {
    <#
    .SYNOPSIS
        An SR's name, tolerating the null reference an unset pool field holds.
    #>
    param($SrRef)
    if (-not $SrRef -or $SrRef.opaque_ref -eq "OpaqueRef:NULL") { return "(none)" }
    (Get-XenSR -Ref $SrRef.opaque_ref).name_label
}
```

<details><summary>Example output</summary>

```text
default storage:  Shared NFS
  suspend images: Shared NFS
  crash dumps:    (none)
  switched to:    sdk-example-default
  restored to:    Shared NFS
OK: set-default-sr
```

</details>

## xe CLI

Source: [`cli/storage/set-default-sr.sh`](../../cli/storage/set-default-sr.sh)

```bash
# Set the pool's default storage.
#
# Choose where the pool puts new disks, suspended VMs' memory images and host crash dumps by default, then put
# the original choice back.
#
# Run it:
#   ./workflows.sh set-default-sr https://xenserver root "$password"
#
# Optional key=value arguments (default):
#   nfs_server (192.0.2.10)
#   nfs_path (/export/spare)

set_default_sr() {
    pool=$(first_csv "$(xe pool-list --minimal)")

    # Three independent settings: where new disks go, where a suspended VM's memory image is written and
    # where host crash dumps land. Capture each - a pool that has never suspended or crashed anything can
    # legitimately leave the latter two unset, so restoring all three from the default would quietly
    # invent settings that were not there. xe prints and accepts these as UUIDs.
    before=$(pool_sr_setting $pool default-SR)
    before_suspend=$(pool_sr_setting $pool suspend-image-SR)
    before_crash=$(pool_sr_setting $pool crash-dump-SR)
    echo "default storage:  $(sr_label "$before")"
    echo "  suspend images: $(sr_label "$before_suspend")"
    echo "  crash dumps:    $(sr_label "$before_crash")"

    # Somewhere to switch to. The pool default has to be reachable from every host, so it is shared
    # storage; a local SR would strand any VM whose disk landed on the wrong host.
    sr=$(xe sr-create name-label=xe-example-default type=nfs content-type=user shared=true \
        device-config:server="$(param nfs_server 192.0.2.10)" \
        device-config:serverpath="$(param nfs_path /export/spare)" device-config:nfsversion=3)
    xe pool-param-set uuid=$pool default-SR=$sr suspend-image-SR=$sr crash-dump-SR=$sr
    echo "  switched to:    $(sr_label "$(xe pool-param-get uuid=$pool param-name=default-SR)")"

    # Put the original choice back before tidying up: storage that is still the pool default is the
    # awkward thing to remove.
    xe pool-param-set uuid=$pool default-SR=$before suspend-image-SR=$before_suspend crash-dump-SR=$before_crash
    for pbd in $(each_csv "$(xe pbd-list sr-uuid=$sr --minimal)"); do xe pbd-unplug uuid=$pbd; done
    xe sr-forget uuid=$sr
    echo "  restored to:    $(sr_label "$(xe pool-param-get uuid=$pool param-name=default-SR)")"
    echo "OK: set-default-sr"
}

# An SR's name from its UUID, tolerating the empty value an unset pool setting prints.
sr_label() {
    if [ -z "$1" ]; then echo "(none)"; else xe sr-param-get uuid=$1 param-name=name-label; fi
}

# One of the pool's SR settings, as a uuid or "" when unset. xe prints an unset reference as
# "<not in database>", but setting one takes "" to mean unset - so map one to the other, or the value
# read cannot be written back.
pool_sr_setting() {
    local v
    v=$(xe pool-param-get uuid=$1 param-name=$2)
    [ "$v" = "<not in database>" ] && v=""
    echo "$v"
}
```

<details><summary>Example output</summary>

```text
default storage:  Shared NFS
  suspend images: Shared NFS
  crash dumps:    (none)
  switched to:    xe-example-default
  restored to:    Shared NFS
OK: set-default-sr
```

</details>

## Python

Source: [`python/storage/set_default_sr.py`](../../python/storage/set_default_sr.py)

```python
"""Set the pool's default storage.

Choose where the pool puts new disks, suspended VMs' memory images and host crash dumps by default,
then put the original choice back.
"""

from connection import connect


def set_default_sr(url, username, password, nfs_server="192.0.2.10", nfs_path="/export/spare"):
    """Choose where the pool puts new disks, suspended VMs and crash dumps by default.

    These are three separate settings, not one. New disks land on the default SR, a
    suspended VM's memory image goes to the suspend-image SR and host crash dumps to the
    crash-dump SR -- they are usually the same storage, but they need not be."""
    session = connect(url, username, password)
    x = session.xenapi
    pool = x.pool.get_all()[0]

    # Capture all three separately. They are genuinely independent, and a pool that has
    # never suspended or crashed anything can legitimately leave the latter two unset -- so
    # restoring all three from the default would quietly invent settings that were not there.
    before = x.pool.get_default_SR(pool)
    before_suspend = x.pool.get_suspend_image_SR(pool)
    before_crash = x.pool.get_crash_dump_SR(pool)
    print("default storage:  %s" % sr_label(x, before))
    print("  suspend images: %s" % sr_label(x, before_suspend))
    print("  crash dumps:    %s" % sr_label(x, before_crash))

    # Somewhere to switch to. A pool default has to be reachable from every host, so it is
    # a shared SR; a local one would strand any VM whose disk landed on the wrong host.
    sr = x.SR.create(host_first(x), {"server": nfs_server, "serverpath": nfs_path, "nfsversion": "3"},
                     "0", "sdk-example-default", "SR used by the SDK default-storage example",
                     "nfs", "user", True, {})
    x.pool.set_default_SR(pool, sr)
    x.pool.set_suspend_image_SR(pool, sr)
    x.pool.set_crash_dump_SR(pool, sr)
    print("  switched to:    %s" % sr_label(x, x.pool.get_default_SR(pool)))

    # Restore the original choice before tidying up: an SR that is still the pool default is
    # the awkward one to remove.
    x.pool.set_default_SR(pool, before)
    x.pool.set_suspend_image_SR(pool, before_suspend)
    x.pool.set_crash_dump_SR(pool, before_crash)
    for pbd in x.SR.get_PBDs(sr):
        x.PBD.unplug(pbd)
    x.SR.forget(sr)
    print("  restored to:    %s" % sr_label(x, x.pool.get_default_SR(pool)))
    print("OK: set-default-sr")
    session.logout()


def host_first(x):
    return x.host.get_all()[0]


def sr_label(x, sr):
    """An SR's name, tolerating the null reference an unset pool field holds."""
    return x.SR.get_name_label(sr) if sr and sr != "OpaqueRef:NULL" else "(none)"
```

<details><summary>Example output</summary>

```text
default storage:  Shared NFS
  suspend images: Shared NFS
  crash dumps:    (none)
  switched to:    sdk-example-default
  restored to:    Shared NFS
OK: set-default-sr
```

</details>

## C# (.NET)

Source: [`csharp/Storage/SetDefaultSr.cs`](../../csharp/Storage/SetDefaultSr.cs)

```csharp
/// <summary>
/// Choose where the pool puts new disks, suspended VMs' memory images and host crash dumps by default,
/// then put the original choice back.
/// </summary>
public static void SetDefaultSr(string url, string user, string password,
    string nfsServer = "192.0.2.10", string nfsPath = "/export/spare")
{
    var session = Connect(url, user, password);
    var pool = Pool.get_all(session).First().opaque_ref;

    // Capture all three separately. New disks land on the default SR, a suspended VM's memory image
    // goes to the suspend-image SR and host crash dumps to the crash-dump SR. They are usually the
    // same storage but need not be, and a pool that has never suspended or crashed anything can
    // legitimately leave the latter two unset — so restoring all three from the default would
    // quietly invent settings that were not there.
    var before = Pool.get_default_SR(session, pool).opaque_ref;
    var beforeSuspend = Pool.get_suspend_image_SR(session, pool).opaque_ref;
    var beforeCrash = Pool.get_crash_dump_SR(session, pool).opaque_ref;
    Console.WriteLine($"default storage:  {SrLabel(session, before)}");
    Console.WriteLine($"  suspend images: {SrLabel(session, beforeSuspend)}");
    Console.WriteLine($"  crash dumps:    {SrLabel(session, beforeCrash)}");

    // Somewhere to switch to. A pool default has to be reachable from every host, so it is a shared
    // SR; a local one would strand any VM whose disk landed on the wrong host.
    var sr = SR.create(session, Host.get_all(session).First().opaque_ref,
        new Dictionary<string, string>
        {
            ["server"] = nfsServer,
            ["serverpath"] = nfsPath,
            ["nfsversion"] = "3",
        }, 0, "sdk-example-default", "SR used by the SDK default-storage example",
        "nfs", "user", true, new Dictionary<string, string>()).opaque_ref;

    Pool.set_default_SR(session, pool, sr);
    Pool.set_suspend_image_SR(session, pool, sr);
    Pool.set_crash_dump_SR(session, pool, sr);
    Console.WriteLine($"  switched to:    {SrLabel(session, Pool.get_default_SR(session, pool).opaque_ref)}");

    // Restore the original choice before tidying up: an SR that is still the pool default is the
    // awkward one to remove.
    Pool.set_default_SR(session, pool, before);
    Pool.set_suspend_image_SR(session, pool, beforeSuspend);
    Pool.set_crash_dump_SR(session, pool, beforeCrash);
    foreach (var pbd in SR.get_PBDs(session, sr)) PBD.unplug(session, pbd.opaque_ref);
    SR.forget(session, sr);
    Console.WriteLine($"  restored to:    {SrLabel(session, Pool.get_default_SR(session, pool).opaque_ref)}");
    Console.WriteLine("OK: set-default-sr");
    session.logout();
}

/// <summary>An SR's name, tolerating the null reference an unset pool field holds.</summary>
private static string SrLabel(Session session, string sr) =>
    string.IsNullOrEmpty(sr) || sr == "OpaqueRef:NULL" ? "(none)" : SR.get_name_label(session, sr);
```

<details><summary>Example output</summary>

```text
default storage:  Shared NFS
  suspend images: Shared NFS
  crash dumps:    (none)
  switched to:    sdk-example-default
  restored to:    Shared NFS
OK: set-default-sr
```

</details>

## Go

Source: [`go/set_default_sr.go`](../../go/set_default_sr.go)

```go
package main

import (
	"fmt"

	"go/xenapi"
)

// setDefaultSr - Set the pool's default storage.
//
// Choose where the pool puts new disks, suspended VMs' memory images and host crash dumps by
// default, then put the original choice back.
func setDefaultSr(url, user, password, nfsServer, nfsPath string) {
	session := connect(url, user, password)
	defer session.Logout()

	pools, err := xenapi.Pool.GetAll(session)
	check(err)
	pool := pools[0]

	// Capture all three separately. New disks land on the default SR, a suspended VM's memory image goes
	// to the suspend-image SR and host crash dumps to the crash-dump SR. They are usually the same
	// storage but need not be, and a pool that has never suspended or crashed anything can legitimately
	// leave the latter two unset - so restoring all three from the default would quietly invent settings
	// that were not there.
	before, err := xenapi.Pool.GetDefaultSR(session, pool)
	check(err)
	beforeSuspend, err := xenapi.Pool.GetSuspendImageSR(session, pool)
	check(err)
	beforeCrash, err := xenapi.Pool.GetCrashDumpSR(session, pool)
	check(err)
	fmt.Printf("default storage:  %s\n", srLabel(session, before))
	fmt.Printf("  suspend images: %s\n", srLabel(session, beforeSuspend))
	fmt.Printf("  crash dumps:    %s\n", srLabel(session, beforeCrash))

	// Somewhere to switch to. A pool default has to be reachable from every host, so it is a shared SR;
	// a local one would strand any VM whose disk landed on the wrong host.
	hosts, err := xenapi.Host.GetAll(session)
	check(err)
	sr, err := xenapi.SR.Create(session, hosts[0], map[string]string{
		"server":     nfsServer,
		"serverpath": nfsPath,
		"nfsversion": "3",
	}, 0, "sdk-example-default", "SR used by the SDK default-storage example",
		"nfs", "user", true, map[string]string{})
	check(err)

	check(xenapi.Pool.SetDefaultSR(session, pool, sr))
	check(xenapi.Pool.SetSuspendImageSR(session, pool, sr))
	check(xenapi.Pool.SetCrashDumpSR(session, pool, sr))
	now, _ := xenapi.Pool.GetDefaultSR(session, pool)
	fmt.Printf("  switched to:    %s\n", srLabel(session, now))

	// Restore the original choice before tidying up: an SR that is still the pool default is the awkward
	// one to remove.
	check(xenapi.Pool.SetDefaultSR(session, pool, before))
	check(xenapi.Pool.SetSuspendImageSR(session, pool, beforeSuspend))
	check(xenapi.Pool.SetCrashDumpSR(session, pool, beforeCrash))
	pbds, err := xenapi.SR.GetPBDs(session, sr)
	check(err)
	for _, pbd := range pbds {
		check(xenapi.PBD.Unplug(session, pbd))
	}
	check(xenapi.SR.Forget(session, sr))
	restored, _ := xenapi.Pool.GetDefaultSR(session, pool)
	fmt.Printf("  restored to:    %s\n", srLabel(session, restored))
	fmt.Println("OK: set-default-sr")
}
```

<details><summary>Example output</summary>

```text
default storage:  Shared NFS
  suspend images: Shared NFS
  crash dumps:    (none)
  switched to:    sdk-example-default
  restored to:    Shared NFS
OK: set-default-sr
```

</details>

## Java

Source: [`java/src/main/java/com/xenserver/samples/storage/SetDefaultSr.java`](../../java/src/main/java/com/xenserver/samples/storage/SetDefaultSr.java)

```java
package com.xenserver.samples.storage;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.Host;
import com.xensource.xenapi.PBD;
import com.xensource.xenapi.Pool;
import com.xensource.xenapi.SR;
import com.xensource.xenapi.Session;

import java.util.Map;

import static com.xenserver.samples.PoolConnection.connect;

public final class SetDefaultSr {
    private SetDefaultSr() {
    }

    /**
     * Set the pool's default storage.
     *
     * <p>Choose where the pool puts new disks, suspended VMs' memory images and host crash dumps by
     * default, then put the original choice back.
     */
    public static void run(String url, String user, String password,
            String nfsServer, String nfsPath) throws Exception {
        Connection conn = connect(url, user, password);
        try {
            Pool pool = Pool.getAll(conn).iterator().next();

            // Capture all three separately. New disks land on the default SR, a suspended VM's memory
            // image goes to the suspend-image SR and host crash dumps to the crash-dump SR. They are
            // usually the same storage but need not be, and a pool that has never suspended or crashed
            // anything can legitimately leave the latter two unset - so restoring all three from the
            // default would quietly invent settings that were not there.
            SR before = pool.getDefaultSR(conn);
            SR beforeSuspend = pool.getSuspendImageSR(conn);
            SR beforeCrash = pool.getCrashDumpSR(conn);
            System.out.println("default storage:  " + srLabel(conn, before));
            System.out.println("  suspend images: " + srLabel(conn, beforeSuspend));
            System.out.println("  crash dumps:    " + srLabel(conn, beforeCrash));

            // Somewhere to switch to. A pool default has to be reachable from every host, so it is a
            // shared SR; a local one would strand any VM whose disk landed on the wrong host.
            Map<String, String> deviceConfig = new java.util.HashMap<>();
            deviceConfig.put("server", nfsServer);
            deviceConfig.put("serverpath", nfsPath);
            deviceConfig.put("nfsversion", "3");
            SR sr = SR.create(conn, Host.getAll(conn).iterator().next(), deviceConfig, 0L,
                "sdk-example-default", "SR used by the SDK default-storage example",
                "nfs", "user", true, new java.util.HashMap<>());

            pool.setDefaultSR(conn, sr);
            pool.setSuspendImageSR(conn, sr);
            pool.setCrashDumpSR(conn, sr);
            System.out.println("  switched to:    " + srLabel(conn, pool.getDefaultSR(conn)));

            // Restore the original choice before tidying up: an SR that is still the pool default is
            // the awkward one to remove.
            pool.setDefaultSR(conn, before);
            pool.setSuspendImageSR(conn, beforeSuspend);
            pool.setCrashDumpSR(conn, beforeCrash);
            for (PBD pbd : sr.getPBDs(conn)) pbd.unplug(conn);
            sr.forget(conn);
            System.out.println("  restored to:    " + srLabel(conn, pool.getDefaultSR(conn)));
            System.out.println("OK: set-default-sr");
        } finally {
            Session.logout(conn);
        }
    }

    /**
     * An SR's name, tolerating the null reference an unset pool field holds.
     */
    private static String srLabel(Connection conn, SR sr) throws Exception {
        if (sr == null || sr.toWireString() == null || sr.toWireString().equals("OpaqueRef:NULL"))
            return "(none)";
        return sr.getNameLabel(conn);
    }
}
```

<details><summary>Example output</summary>

```text
default storage:  Shared NFS
  suspend images: Shared NFS
  crash dumps:    (none)
  switched to:    sdk-example-default
  restored to:    Shared NFS
OK: set-default-sr
```

</details>
