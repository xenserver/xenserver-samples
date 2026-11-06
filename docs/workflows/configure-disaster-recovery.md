<!-- Generated from workflows.json, the example sources and a run of each example. Edit those, not this file. -->

# Configure disaster recovery

Replicate the pool's metadata (the configuration of its VMs and vApps) to an iSCSI or Fibre Channel SR, so that a pool at a disaster recovery site can recover the VMs from the storage array's replica of that SR.

**Requires:** an iSCSI or Fibre Channel SR attached to every host.

Workflow `configure-disaster-recovery`. [All workflows](README.md) · [Connecting](connecting.md)

## PowerShell

Source: [`powershell/DisasterRecovery/Invoke-ConfigureDisasterRecovery.ps1`](../../powershell/DisasterRecovery/Invoke-ConfigureDisasterRecovery.ps1)

```powershell
function Invoke-ConfigureDisasterRecovery {
    <#
    .SYNOPSIS
        Configure disaster recovery.
    .DESCRIPTION
        Turn on pool metadata replication: the pool writes its database - the configuration of its VMs and
        vApps - to a disk on an iSCSI or Fibre Channel SR. Have your storage array replicate that SR, and
        the VMs' SRs, to the disaster recovery site; a pool there can then recover the VMs from the replica
        (see Invoke-DisasterRecoveryFailover).
    .EXAMPLE
        Invoke-ConfigureDisasterRecovery -Url https://xenserver -UserName root -Password $password
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password,
        [string]$SrName
    )
    # Only SRs on a LUN - iSCSI or Fibre Channel/SAS (HBA) - can hold the pool's database, and every host
    # must have the SR attached. The server says which qualify: SR.assert_supports_database_replication
    # fails for any that can't (an NFS SR fails SR_OPERATION_NOT_SUPPORTED), so ask each one rather than
    # guessing from its type. A pool can replicate to up to 8 SRs.
    #
    # Replication is only useful while it is on. So that the example leaves the pool as it found it, it
    # turns replication off again if it was off to start with; in practice, leave it on.
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password

    $candidates = @(Get-XenSR | Where-Object { $_.shared -and $_.content_type -ne 'iso' } | Where-Object {
            try {
                $_ | Invoke-XenSR -XenAction AssertSupportsDatabaseReplication
                $true
            }
            catch { $false }
        })
    $names = ($candidates | ForEach-Object { $_.name_label }) -join ', '
    Write-Host "SRs that can hold the pool metadata: $(if ($names) { $names } else { 'none' })"
    if ($SrName) { $candidates = @($candidates | Where-Object { $_.name_label -eq $SrName }) }
    if ($candidates.Count -eq 0) {
        $named = if ($SrName) { " named '$SrName'" } else { "" }
        throw "no SR here can hold the pool metadata${named}: it needs an iSCSI or Fibre Channel SR attached to every host"
    }
    $sr = $candidates[0]

    # The pool's own metadata disk on this SR is what says replication is on: a disk of type metadata whose
    # metadata_of_pool is this pool.
    $pool = Get-XenPool
    $metadataDisk = {
        Get-XenVDI | Where-Object {
            $_.type -eq 'metadata' -and $_.SR -eq $sr -and
            $_.metadata_of_pool -eq $pool
        } | Select-Object -First 1
    }

    $wasOn = [bool](& $metadataDisk)
    if ($wasOn) {
        Write-Host "The pool metadata is already replicated to $($sr.name_label)"
    }
    else {
        Write-Host "Replicating the pool metadata to $($sr.name_label)"
        $sr | Invoke-XenSR -XenAction EnableDatabaseReplication
    }

    $vdi = & $metadataDisk
    Write-Host ("  metadata disk: {0} ({1}), {2} MiB, up to date: {3}" -f $vdi.name_label, $vdi.uuid,
        ($vdi.virtual_size / 1MB), $vdi.metadata_latest)

    if (-not $wasOn) {
        # Turning replication off destroys the metadata disk.
        $sr | Invoke-XenSR -XenAction DisableDatabaseReplication
        Write-Host "Turned replication off again, as it was before"
    }
    Write-Host "OK: configure-disaster-recovery"
    $session | Disconnect-XenServer
}
```

<details><summary>Example output</summary>

```text
SRs that can hold the pool metadata: iSCSI storage
Replicating the pool metadata to iSCSI storage
  metadata disk: Metadata for DR (00000001-0000-0000-530b-000000000000), 3804 MiB, up to date: True
Turned replication off again, as it was before
OK: configure-disaster-recovery
```

</details>

## xe CLI

Source: [`cli/disaster-recovery/configure-disaster-recovery.sh`](../../cli/disaster-recovery/configure-disaster-recovery.sh)

```bash
# Configure disaster recovery.
#
# Turn on pool metadata replication: the pool writes its database - the configuration of its VMs and vApps
# - to a disk on an iSCSI or Fibre Channel SR. Have your storage array replicate that SR, and the VMs'
# SRs, to the disaster recovery site; a pool there can then recover the VMs from the replica (see
# disaster-recovery-failover).
#
# Run it:
#   ./workflows.sh configure-disaster-recovery https://xenserver root "$password"
#
# Optional key=value arguments (default):
#   sr_name ("")

# Only SRs on a LUN - iSCSI or Fibre Channel/SAS (HBA) - can hold the pool's database, and every host must
# have the SR attached. The server checks both before it agrees: its storage driver must have the
# SR_METADATA feature (NFS and local storage don't), and every host a plugged PBD. xe has no command that
# asks it, so check the same two things here. A pool can replicate to up to 8 SRs.
#
# Replication is only useful while it is on. So that the example leaves the pool as it found it, it turns
# replication off again if it was off to start with; in practice, leave it on.
configure_disaster_recovery() {
    local sr_name hosts candidate type sr name pool vdi was_on t
    local -a candidates=() names=()
    sr_name=$(param sr_name "")
    hosts=$(count_csv "$(xe host-list --minimal)")
    for candidate in $(each_csv "$(xe sr-list shared=true --minimal)"); do
        type=$(xe sr-param-get uuid=$candidate param-name=type)
        [[ $(xe sm-list type=$type params=features --minimal) == *SR_METADATA* ]] || continue
        [ "$(count_csv "$(xe pbd-list sr-uuid=$candidate currently-attached=true --minimal)")" = "$hosts" ] || continue
        candidates+=("$candidate")
        names+=("$(xe sr-param-get uuid=$candidate param-name=name-label)")
    done
    echo "SRs that can hold the pool metadata: $( ((${#names[@]})) && (IFS=,; echo "${names[*]}" | sed 's/,/, /g') || echo none)"
    sr=""
    for candidate in "${candidates[@]}"; do
        if [ -z "$sr_name" ] || [ "$(xe sr-param-get uuid=$candidate param-name=name-label)" = "$sr_name" ]; then
            sr=$candidate; break
        fi
    done
    if [ -z "$sr" ]; then
        echo "no SR here can hold the pool metadata${sr_name:+ named '$sr_name'}: it needs an iSCSI or Fibre Channel SR attached to every host" >&2
        exit 1
    fi
    name=$(xe sr-param-get uuid=$sr param-name=name-label)

    # The pool's own metadata disk on this SR is what says replication is on: a disk of type metadata whose
    # metadata-of-pool is this pool. xe shows the type as "Metadata", so compare it case-insensitively.
    pool=$(xe pool-list --minimal)
    metadata_disk() {
        local v
        for v in $(each_csv "$(xe vdi-list sr-uuid=$sr --minimal)"); do
            t=$(xe vdi-param-get uuid=$v param-name=type)
            if [ "${t,,}" = metadata ] && [ "$(xe vdi-param-get uuid=$v param-name=metadata-of-pool)" = "$pool" ]; then
                echo "$v"; return
            fi
        done
    }

    was_on=false
    if [ -n "$(metadata_disk)" ]; then
        was_on=true
        echo "The pool metadata is already replicated to $name"
    else
        echo "Replicating the pool metadata to $name"
        xe sr-enable-database-replication uuid=$sr
    fi

    vdi=$(metadata_disk)
    echo "  metadata disk: $(xe vdi-param-get uuid=$vdi param-name=name-label) ($vdi)," \
        "$(($(xe vdi-param-get uuid=$vdi param-name=virtual-size) / 1048576)) MiB," \
        "up to date: $(xe vdi-param-get uuid=$vdi param-name=metadata-latest)"

    if [ "$was_on" = false ]; then
        # Turning replication off destroys the metadata disk.
        xe sr-disable-database-replication uuid=$sr
        echo "Turned replication off again, as it was before"
    fi
    echo "OK: configure-disaster-recovery"
}
```

<details><summary>Example output</summary>

```text
SRs that can hold the pool metadata: iSCSI storage
Replicating the pool metadata to iSCSI storage
  metadata disk: Metadata for DR (00000001-0000-0000-570b-000000000000), 3804 MiB, up to date: true
Turned replication off again, as it was before
OK: configure-disaster-recovery
```

</details>

## Python

Source: [`python/disaster_recovery/configure_disaster_recovery.py`](../../python/disaster_recovery/configure_disaster_recovery.py)

```python
"""Configure disaster recovery.

Turn on pool metadata replication: the pool writes its database - the configuration of its VMs and
vApps - to a disk on an iSCSI or Fibre Channel SR. Have your storage array replicate that SR, and the
VMs' SRs, to the disaster recovery site; a pool there can then recover the VMs from the replica (see
disaster_recovery_failover).

Run it::

    configure_disaster_recovery("https://xenserver", "root", password)
"""

import XenAPI

from connection import connect


def configure_disaster_recovery(url, username, password, sr_name=None):
    """Replicate the pool's metadata to an SR that can hold it (sr_name, or the first that can).

    Only SRs on a LUN - iSCSI or Fibre Channel/SAS (HBA) - can hold the pool's database, and every
    host must have the SR attached. The server says which qualify: SR.assert_supports_database_replication
    fails for any that can't (an NFS SR fails SR_OPERATION_NOT_SUPPORTED), so ask each one rather than
    guessing from its type. A pool can replicate to up to 8 SRs.

    Replication is only useful while it is on. So that the example leaves the pool as it found it, it
    turns replication off again if it was off to start with; in practice, leave it on."""
    session = connect(url, username, password)
    x = session.xenapi

    def supports_replication(sr):
        try:
            x.SR.assert_supports_database_replication(sr)
            return True
        except XenAPI.Failure:
            return False

    candidates = [sr for sr, r in x.SR.get_all_records().items()
                  if r["shared"] and r["content_type"] != "iso" and supports_replication(sr)]
    print("SRs that can hold the pool metadata: %s"
          % (", ".join(x.SR.get_name_label(sr) for sr in candidates) or "none"))
    if sr_name:
        candidates = [sr for sr in candidates if x.SR.get_name_label(sr) == sr_name]
    if not candidates:
        raise RuntimeError("no SR here can hold the pool metadata%s: it needs an iSCSI or Fibre Channel "
                           "SR attached to every host" % (" named %r" % sr_name if sr_name else ""))
    sr = candidates[0]
    name = x.SR.get_name_label(sr)

    # The pool's own metadata disk on this SR is what says replication is on: a disk of type "metadata" whose
    # metadata_of_pool is this pool.
    pool = x.pool.get_all()[0]

    def metadata_disk():
        return next((v for v in x.SR.get_VDIs(sr)
                     if x.VDI.get_type(v) == "metadata" and x.VDI.get_metadata_of_pool(v) == pool), None)

    was_on = metadata_disk() is not None
    if was_on:
        print("The pool metadata is already replicated to %s" % name)
    else:
        print("Replicating the pool metadata to %s" % name)
        x.SR.enable_database_replication(sr)

    vdi = metadata_disk()
    print("  metadata disk: %s (%s), %d MiB, up to date: %s"
          % (x.VDI.get_name_label(vdi), x.VDI.get_uuid(vdi), int(x.VDI.get_virtual_size(vdi)) // (1024 * 1024),
             x.VDI.get_metadata_latest(vdi)))

    if not was_on:
        # Turning replication off destroys the metadata disk.
        x.SR.disable_database_replication(sr)
        print("Turned replication off again, as it was before")
    print("OK: configure-disaster-recovery")
    session.logout()
```

<details><summary>Example output</summary>

```text
SRs that can hold the pool metadata: iSCSI storage
Replicating the pool metadata to iSCSI storage
  metadata disk: Metadata for DR (00000001-0000-0000-b30a-000000000000), 3804 MiB, up to date: True
Turned replication off again, as it was before
OK: configure-disaster-recovery
```

</details>

## C# (.NET)

Source: [`csharp/DisasterRecovery/ConfigureDisasterRecovery.cs`](../../csharp/DisasterRecovery/ConfigureDisasterRecovery.cs)

```csharp
/// <summary>
/// Turn on pool metadata replication: the pool writes its database - the configuration of its VMs and
/// vApps - to a disk on an iSCSI or Fibre Channel SR. Have your storage array replicate that SR, and
/// the VMs' SRs, to the disaster recovery site; a pool there can then recover the VMs from the
/// replica (see <see cref="DisasterRecoveryFailover"/>).
/// </summary>
/// <example>
/// <code>
/// Workflows.ConfigureDisasterRecovery("https://xenserver", "root", password);
/// </code>
/// </example>
/// <remarks>
/// <para>
/// Only SRs on a LUN - iSCSI or Fibre Channel/SAS (HBA) - can hold the pool's database, and every host
/// must have the SR attached. The server says which qualify: SR.assert_supports_database_replication
/// fails for any that can't (an NFS SR fails SR_OPERATION_NOT_SUPPORTED), so ask each one rather than
/// guessing from its type. A pool can replicate to up to 8 SRs.
/// </para>
/// <para>
/// Replication is only useful while it is on. So that the example leaves the pool as it found it, it
/// turns replication off again if it was off to start with; in practice, leave it on.
/// </para>
/// </remarks>
public static void ConfigureDisasterRecovery(string url, string user, string password, string srName = null)
{
    var session = Connect(url, user, password);

    bool SupportsReplication(XenRef<SR> sr)
    {
        try { SR.assert_supports_database_replication(session, sr); return true; }
        catch (Failure) { return false; }
    }
    var candidates = SR.get_all_records(session)
        .Where(kv => kv.Value.shared && kv.Value.content_type != "iso" && SupportsReplication(kv.Key))
        .Select(kv => kv.Key).ToList();
    var names = string.Join(", ", candidates.Select(sr => SR.get_name_label(session, sr)));
    Console.WriteLine($"SRs that can hold the pool metadata: {(names.Length > 0 ? names : "none")}");
    if (!string.IsNullOrEmpty(srName))
        candidates = candidates.Where(sr => SR.get_name_label(session, sr) == srName).ToList();
    if (candidates.Count == 0)
        throw new Exception($"no SR here can hold the pool metadata{(srName != null ? $" named '{srName}'" : "")}: " +
                            "it needs an iSCSI or Fibre Channel SR attached to every host");
    var chosen = candidates[0];
    var name = SR.get_name_label(session, chosen);

    // The pool's own metadata disk on this SR is what says replication is on: a disk of type metadata
    // whose metadata_of_pool is this pool.
    var pool = Pool.get_all(session)[0];
    XenRef<VDI> MetadataDisk() => SR.get_VDIs(session, chosen).FirstOrDefault(v =>
        VDI.get_type(session, v) == vdi_type.metadata && VDI.get_metadata_of_pool(session, v).Equals(pool));

    var wasOn = MetadataDisk() != null;
    if (wasOn)
        Console.WriteLine($"The pool metadata is already replicated to {name}");
    else
    {
        Console.WriteLine($"Replicating the pool metadata to {name}");
        SR.enable_database_replication(session, chosen);
    }

    var vdi = MetadataDisk();
    Console.WriteLine($"  metadata disk: {VDI.get_name_label(session, vdi)} ({VDI.get_uuid(session, vdi)}), " +
                      $"{VDI.get_virtual_size(session, vdi) / (1024 * 1024)} MiB, " +
                      $"up to date: {VDI.get_metadata_latest(session, vdi)}");

    if (!wasOn)
    {
        // Turning replication off destroys the metadata disk.
        SR.disable_database_replication(session, chosen);
        Console.WriteLine("Turned replication off again, as it was before");
    }
    Console.WriteLine("OK: configure-disaster-recovery");
    session.logout();
}
```

<details><summary>Example output</summary>

```text
SRs that can hold the pool metadata: iSCSI storage
Replicating the pool metadata to iSCSI storage
  metadata disk: Metadata for DR (00000001-0000-0000-030b-000000000000), 3804 MiB, up to date: True
Turned replication off again, as it was before
OK: configure-disaster-recovery
```

</details>

## Go

Source: [`go/configure_disaster_recovery.go`](../../go/configure_disaster_recovery.go)

```go
package main

import (
	"fmt"
	"strings"

	"go/xenapi"
)

// configureDisasterRecovery - Configure disaster recovery.
//
// Turn on pool metadata replication: the pool writes its database - the configuration of its VMs and
// vApps - to a disk on an iSCSI or Fibre Channel SR. Have your storage array replicate that SR, and
// the VMs' SRs, to the disaster recovery site; a pool there can then recover the VMs from the
// replica (see disasterRecoveryFailover).
//
// Only SRs on a LUN - iSCSI or Fibre Channel/SAS (HBA) - can hold the pool's database, and every host
// must have the SR attached. The server says which qualify: SR.assert_supports_database_replication fails
// for any that can't (an NFS SR fails SR_OPERATION_NOT_SUPPORTED), so ask each one rather than guessing
// from its type. A pool can replicate to up to 8 SRs.
//
// Replication is only useful while it is on. So that the example leaves the pool as it found it, it
// turns replication off again if it was off to start with; in practice, leave it on.
//
// Run it:
//
//	configureDisasterRecovery("https://xenserver", "root", password, "")
func configureDisasterRecovery(url, user, password, srName string) {
	session := connect(url, user, password)
	defer session.Logout()

	srs, err := xenapi.SR.GetAllRecords(session)
	check(err)
	var candidates []xenapi.SRRef
	var names []string
	for ref, r := range srs {
		if r.Shared && r.ContentType != "iso" && xenapi.SR.AssertSupportsDatabaseReplication(session, ref) == nil {
			candidates = append(candidates, ref)
			names = append(names, r.NameLabel)
		}
	}
	if len(names) == 0 {
		names = []string{"none"}
	}
	fmt.Printf("SRs that can hold the pool metadata: %s\n", strings.Join(names, ", "))
	if srName != "" {
		var named []xenapi.SRRef
		for _, sr := range candidates {
			if srs[sr].NameLabel == srName {
				named = append(named, sr)
			}
		}
		candidates = named
	}
	if len(candidates) == 0 {
		what := ""
		if srName != "" {
			what = fmt.Sprintf(" named %q", srName)
		}
		panic(fmt.Sprintf("no SR here can hold the pool metadata%s: it needs an iSCSI or Fibre Channel "+
			"SR attached to every host", what))
	}
	sr := candidates[0]
	name := srs[sr].NameLabel

	// The pool's own metadata disk on this SR is what says replication is on: a disk of type metadata whose
	// metadata_of_pool is this pool.
	pools, err := xenapi.Pool.GetAll(session)
	check(err)
	metadataDisk := func() xenapi.VDIRef {
		vdis, err := xenapi.SR.GetVDIs(session, sr)
		check(err)
		for _, v := range vdis {
			t, err := xenapi.VDI.GetType(session, v)
			check(err)
			of, err := xenapi.VDI.GetMetadataOfPool(session, v)
			check(err)
			if t == xenapi.VdiTypeMetadata && of == pools[0] {
				return v
			}
		}
		return ""
	}

	wasOn := metadataDisk() != ""
	if wasOn {
		fmt.Printf("The pool metadata is already replicated to %s\n", name)
	} else {
		fmt.Printf("Replicating the pool metadata to %s\n", name)
		check(xenapi.SR.EnableDatabaseReplication(session, sr))
	}

	vdi, err := xenapi.VDI.GetRecord(session, metadataDisk())
	check(err)
	fmt.Printf("  metadata disk: %s (%s), %d MiB, up to date: %t\n",
		vdi.NameLabel, vdi.UUID, vdi.VirtualSize/(1024*1024), vdi.MetadataLatest)

	if !wasOn {
		// Turning replication off destroys the metadata disk.
		check(xenapi.SR.DisableDatabaseReplication(session, sr))
		fmt.Println("Turned replication off again, as it was before")
	}
	fmt.Println("OK: configure-disaster-recovery")
}
```

<details><summary>Example output</summary>

```text
SRs that can hold the pool metadata: iSCSI storage
Replicating the pool metadata to iSCSI storage
  metadata disk: Metadata for DR (00000001-0000-0000-4d0b-000000000000), 3804 MiB, up to date: true
Turned replication off again, as it was before
OK: configure-disaster-recovery
```

</details>

## Java

Source: [`java/src/main/java/com/xenserver/samples/disasterrecovery/ConfigureDisasterRecovery.java`](../../java/src/main/java/com/xenserver/samples/disasterrecovery/ConfigureDisasterRecovery.java)

```java
package com.xenserver.samples.disasterrecovery;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.Pool;
import com.xensource.xenapi.SR;
import com.xensource.xenapi.Session;
import com.xensource.xenapi.Types;
import com.xensource.xenapi.VDI;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.StringJoiner;

import static com.xenserver.samples.PoolConnection.connect;

public final class ConfigureDisasterRecovery {
    private ConfigureDisasterRecovery() {
    }

    /**
     * Configure disaster recovery.
     *
     * <p>Turn on pool metadata replication: the pool writes its database - the configuration of its VMs
     * and vApps - to a disk on an iSCSI or Fibre Channel SR. Have your storage array replicate that SR,
     * and the VMs' SRs, to the disaster recovery site; a pool there can then recover the VMs from the
     * replica (see {@link DisasterRecoveryFailover}).
     *
     * <p>Only SRs on a LUN - iSCSI or Fibre Channel/SAS (HBA) - can hold the pool's database, and every host
     * must have the SR attached. The server says which qualify: SR.assert_supports_database_replication
     * fails for any that can't (an NFS SR fails SR_OPERATION_NOT_SUPPORTED), so ask each one rather than
     * guessing from its type. A pool can replicate to up to 8 SRs.
     *
     * <p>Replication is only useful while it is on. So that the example leaves the pool as it found it, it
     * turns replication off again if it was off to start with; in practice, leave it on.
     *
     * <p>Run it:
     *
     * <pre>{@code
     * ConfigureDisasterRecovery.run("https://xenserver", "root", password, null);
     * }</pre>
     */
    public static void run(String url, String user, String password, String srName) throws Exception {
        Connection conn = connect(url, user, password);
        try {
            List<SR> candidates = new ArrayList<>();
            StringJoiner names = new StringJoiner(", ");
            for (Map.Entry<SR, SR.Record> e : SR.getAllRecords(conn).entrySet()) {
                SR.Record r = e.getValue();
                if (!r.shared || "iso".equals(r.contentType)) continue;
                try {
                    e.getKey().assertSupportsDatabaseReplication(conn);
                } catch (Types.XenAPIException cannot) {
                    continue;
                }
                candidates.add(e.getKey());
                names.add(r.nameLabel);
            }
            System.out.println("SRs that can hold the pool metadata: "
                    + (candidates.isEmpty() ? "none" : names.toString()));
            if (srName != null && !srName.isEmpty()) {
                List<SR> named = new ArrayList<>();
                for (SR sr : candidates)
                    if (srName.equals(sr.getNameLabel(conn))) named.add(sr);
                candidates = named;
            }
            if (candidates.isEmpty())
                throw new RuntimeException("no SR here can hold the pool metadata"
                        + (srName != null && !srName.isEmpty() ? " named '" + srName + "'" : "")
                        + ": it needs an iSCSI or Fibre Channel SR attached to every host");
            SR sr = candidates.get(0);
            String name = sr.getNameLabel(conn);

            // The pool's own metadata disk on this SR is what says replication is on: a disk of type metadata
            // whose metadata_of_pool is this pool.
            Pool pool = Pool.getAll(conn).iterator().next();
            boolean wasOn = metadataDisk(conn, sr, pool) != null;
            if (wasOn) {
                System.out.println("The pool metadata is already replicated to " + name);
            } else {
                System.out.println("Replicating the pool metadata to " + name);
                sr.enableDatabaseReplication(conn);
            }

            VDI vdi = metadataDisk(conn, sr, pool);
            System.out.printf("  metadata disk: %s (%s), %d MiB, up to date: %s%n", vdi.getNameLabel(conn),
                    vdi.getUuid(conn), vdi.getVirtualSize(conn) / (1024 * 1024), vdi.getMetadataLatest(conn));

            if (!wasOn) {
                // Turning replication off destroys the metadata disk.
                sr.disableDatabaseReplication(conn);
                System.out.println("Turned replication off again, as it was before");
            }
            System.out.println("OK: configure-disaster-recovery");
        } finally {
            Session.logout(conn);
        }
    }

    private static VDI metadataDisk(Connection conn, SR sr, Pool pool) throws Exception {
        for (VDI v : sr.getVDIs(conn))
            if (v.getType(conn) == Types.VdiType.METADATA
                    && v.getMetadataOfPool(conn).toWireString().equals(pool.toWireString()))
                return v;
        return null;
    }
}
```

<details><summary>Example output</summary>

```text
SRs that can hold the pool metadata: iSCSI storage
Replicating the pool metadata to iSCSI storage
  metadata disk: Metadata for DR (00000001-0000-0000-300b-000000000000), 3804 MiB, up to date: true
Turned replication off again, as it was before
OK: configure-disaster-recovery
```

</details>
