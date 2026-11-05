<!-- Generated from workflows.json, the example sources and a run of each example. Edit those, not this file. -->

# Configure clustering

Enable the clustering layer that shared block storage needs for thin provisioning, then watch quorum as a host leaves the cluster and rejoins it.

**Requires:** shared block storage for a GFS2 cluster.

Workflow `configure-clustering`. [All workflows](README.md) · [Connecting](connecting.md)

## C# (.NET)

Source: [`csharp/HostsAndPools/ConfigureClustering.cs`](../../csharp/HostsAndPools/ConfigureClustering.cs)

```csharp
/// <summary>
/// Enable the clustering layer that shared block storage needs for thin provisioning, then watch quorum
/// as a host leaves the cluster and rejoins it.
/// </summary>
/// <example>
/// <code>
/// Workflows.ConfigureClustering("https://xenserver", "root", password);
/// </code>
/// </example>
public static void ConfigureClustering(string url, string user, string password)
{
    var session = Connect(url, user, password);

    // Clustering is what shared block storage needs before it can be thin-provisioned with GFS2. Run
    // it over a network every host is on - the management network - since corosync is
    // latency-sensitive and a cluster that loses quorum takes its GFS2 storage offline with it.
    var pifs = PIF.get_all_records(session);
    var network = pifs.First(kv => kv.Value.management).Value.network.opaque_ref;
    var was = pifs.Where(kv => kv.Value.network.opaque_ref == network)
        .ToDictionary(kv => kv.Key.opaque_ref, kv => kv.Value.disallow_unplug);

    var existing = Cluster.get_all(session);
    string cluster;
    if (existing.Count > 0)
        cluster = existing[0].opaque_ref;
    else
    {
        // Corosync must not lose its network, so each host's PIF on it has to refuse unplugging
        // first: Cluster.pool_create fails PIF_ALLOWS_UNPLUG otherwise. was remembers the settings.
        foreach (var pif in was.Keys)
            PIF.set_disallow_unplug(session, pif, true);
        // token_timeout is in seconds (the API's default is 20.0, coefficient 1.0): XS9 refuses 20000
        // as "too large" - it is not milliseconds.
        cluster = Cluster.pool_create(session, network, "corosync", 20.0, 1.0).opaque_ref;
    }

    var record = Cluster.get_record(session, cluster);
    Console.WriteLine($"Stack:      {record.cluster_stack}");
    Console.WriteLine($"Quorate:    {record.is_quorate} ({record.live_hosts}/{record.quorum} needed)");

    // Taking a host out is what a management-interface change does; it can cost the pool quorum,
    // which is why the field is worth reading back rather than assuming.
    var member = Cluster_host.get_all(session)[0].opaque_ref;
    Cluster_host.disable(session, member);
    Console.WriteLine($"One member out, quorate: {Cluster.get_is_quorate(session, cluster)}");

    Cluster_host.enable(session, member);
    Cluster.pool_resync(session, cluster);
    Console.WriteLine($"Resynced,   quorate: {Cluster.get_is_quorate(session, cluster)}");

    // Tidy up a cluster this example created (one that was already there stays), and the PIF settings.
    if (existing.Count == 0)
    {
        Cluster.pool_destroy(session, cluster);
        foreach (var (pif, value) in was)
            PIF.set_disallow_unplug(session, pif, value);
        Console.WriteLine("Cluster removed again.");
    }

    Console.WriteLine("OK: configure-clustering");
    session.logout();
}
```

<details><summary>Sample output</summary>

```text
Stack:      corosync
Quorate:    True (2/2 needed)
One member out, quorate: False
Resynced,   quorate: True
Cluster removed again.
OK: configure-clustering
```

</details>

## Python

Source: [`python/hosts_and_pools/configure_clustering.py`](../../python/hosts_and_pools/configure_clustering.py)

```python
"""Configure clustering.

Enable the clustering layer that shared block storage needs for thin provisioning, then watch quorum
as a host leaves the cluster and rejoins it.

Run it::

    configure_clustering("https://xenserver", "root", password)
"""

from connection import connect


def configure_clustering(url, username, password):
    """Enable corosync clustering, watch quorum as a member leaves and rejoins."""
    session = connect(url, username, password)
    x = session.xenapi

    # Clustering is what shared block storage needs before it can be thin-provisioned with GFS2. Run it
    # over a network every host is on - the management network - since corosync is latency-sensitive and
    # a cluster that loses quorum takes its GFS2 storage offline with it.
    pifs = x.PIF.get_all_records()
    network = next(r["network"] for r in pifs.values() if r["management"])
    network_pifs = [ref for ref, r in pifs.items() if r["network"] == network]

    existing = x.Cluster.get_all()
    if existing:
        cluster = existing[0]
    else:
        # Corosync must not lose its network, so each host's PIF on it has to refuse unplugging first:
        # Cluster.pool_create fails PIF_ALLOWS_UNPLUG otherwise. Remember the settings to restore them.
        was = {ref: pifs[ref]["disallow_unplug"] for ref in network_pifs}
        for ref in network_pifs:
            x.PIF.set_disallow_unplug(ref, True)
        # token_timeout is in seconds (the API's default is 20.0, coefficient 1.0): XS9 refuses 20000 as
        # "too large" - it is not milliseconds.
        cluster = x.Cluster.pool_create(network, "corosync", 20.0, 1.0)

    record = x.Cluster.get_record(cluster)
    print(f"Stack:      {record['cluster_stack']}")
    print(f"Quorate:    {record['is_quorate']} ({record['live_hosts']}/{record['quorum']} needed)")

    # Taking a host out is what a management-interface change does; it can cost the pool quorum, which
    # is why the field is worth reading back rather than assuming.
    member = x.Cluster_host.get_all()[0]
    x.Cluster_host.disable(member)
    print(f"One member out, quorate: {x.Cluster.get_is_quorate(cluster)}")

    x.Cluster_host.enable(member)
    x.Cluster.pool_resync(cluster)
    print(f"Resynced,   quorate: {x.Cluster.get_is_quorate(cluster)}")

    # Tidy up a cluster this example created (one that was already there stays), and the PIF settings.
    if not existing:
        x.Cluster.pool_destroy(cluster)
        for ref, value in was.items():
            x.PIF.set_disallow_unplug(ref, value)
        print("Cluster removed again.")

    print("OK: configure-clustering")
    x.session.logout()
```

<details><summary>Sample output</summary>

```text
Stack:      corosync
Quorate:    True (2/2 needed)
One member out, quorate: False
Resynced,   quorate: True
Cluster removed again.
OK: configure-clustering
```

</details>

## Java

Source: [`java/src/main/java/com/xenserver/samples/hostsandpools/ConfigureClustering.java`](../../java/src/main/java/com/xenserver/samples/hostsandpools/ConfigureClustering.java)

```java
package com.xenserver.samples.hostsandpools;

import com.xensource.xenapi.Cluster;
import com.xensource.xenapi.ClusterHost;
import com.xensource.xenapi.Connection;
import com.xensource.xenapi.Network;
import com.xensource.xenapi.PIF;
import com.xensource.xenapi.Session;

import java.util.HashMap;
import java.util.Map;
import java.util.Set;

import static com.xenserver.samples.PoolConnection.connect;

public final class ConfigureClustering {
    private ConfigureClustering() {
    }

    /**
     * Configure clustering.
     *
     * <p>Enable the clustering layer that shared block storage needs for thin provisioning, then watch
     * quorum as a host leaves the cluster and rejoins it.
     *
     * <p>Run it:
     *
     * <pre>{@code
     * ConfigureClustering.run("https://xenserver", "root", password);
     * }</pre>
     */
    public static void run(String url, String user, String password) throws Exception {
        Connection conn = connect(url, user, password);
        try {
            // Clustering is what shared block storage needs before GFS2 thin provisioning. Run it over a
            // network every host is on - the management network - since corosync is latency-sensitive
            // and a cluster that loses quorum takes its GFS2 storage offline with it.
            Map<PIF, PIF.Record> pifs = PIF.getAllRecords(conn);
            Network network = null;
            for (PIF.Record r : pifs.values()) {
                if (r.management) { network = r.network; break; }
            }
            Map<PIF, Boolean> was = new HashMap<>();
            for (Map.Entry<PIF, PIF.Record> e : pifs.entrySet()) {
                if (e.getValue().network.equals(network)) was.put(e.getKey(), e.getValue().disallowUnplug);
            }

            Set<Cluster> existing = Cluster.getAll(conn);
            Cluster cluster;
            if (!existing.isEmpty()) {
                cluster = existing.iterator().next();
            } else {
                // Corosync must not lose its network, so each host's PIF on it has to refuse unplugging
                // first: Cluster.poolCreate fails PIF_ALLOWS_UNPLUG otherwise. was remembers the settings.
                for (PIF pif : was.keySet()) pif.setDisallowUnplug(conn, true);
                // token_timeout is in seconds (the API's default is 20.0, coefficient 1.0): XS9 refuses
                // 20000 as "too large" - it is not milliseconds.
                cluster = Cluster.poolCreate(conn, network, "corosync", 20.0, 1.0);
            }

            System.out.println("Stack:      " + cluster.getClusterStack(conn));
            System.out.println("Quorate:    " + cluster.getIsQuorate(conn)
                    + " (" + cluster.getLiveHosts(conn) + "/" + cluster.getQuorum(conn) + " needed)");

            // Taking a host out is what a management-interface change does; it can cost quorum.
            ClusterHost member = ClusterHost.getAll(conn).iterator().next();
            member.disable(conn);
            System.out.println("One member out, quorate: " + cluster.getIsQuorate(conn));

            member.enable(conn);
            cluster.poolResync(conn);
            System.out.println("Resynced,   quorate: " + cluster.getIsQuorate(conn));

            // Tidy up a cluster this example created (one that was already there stays), and the PIF
            // settings.
            if (existing.isEmpty()) {
                cluster.poolDestroy(conn);
                for (Map.Entry<PIF, Boolean> e : was.entrySet()) e.getKey().setDisallowUnplug(conn, e.getValue());
                System.out.println("Cluster removed again.");
            }

            System.out.println("OK: configure-clustering");
        } finally {
            Session.logout(conn);
        }
    }
}
```

<details><summary>Sample output</summary>

```text
Stack:      corosync
Quorate:    true (2/2 needed)
One member out, quorate: false
Resynced,   quorate: true
Cluster removed again.
OK: configure-clustering
```

</details>

## Go

Source: [`go/configure_clustering.go`](../../go/configure_clustering.go)

```go
package main

import (
	"fmt"

	"go/xenapi"
)

// configureClustering - Configure clustering.
//
// Enable the clustering layer that shared block storage needs for thin provisioning, then watch
// quorum as a host leaves the cluster and rejoins it.
func configureClustering(url, user, password string) {
	session := connect(url, user, password)

	// Clustering is what shared block storage needs before GFS2 thin provisioning. Run it over a network
	// every host is on - the management network - since corosync is latency-sensitive and a cluster that
	// loses quorum takes its GFS2 storage offline with it.
	pifs, err := xenapi.PIF.GetAllRecords(session)
	check(err)
	var network xenapi.NetworkRef
	for _, p := range pifs {
		if p.Management {
			network = p.Network
			break
		}
	}
	was := map[xenapi.PIFRef]bool{}
	for ref, p := range pifs {
		if p.Network == network {
			was[ref] = p.DisallowUnplug
		}
	}

	existing, err := xenapi.Cluster.GetAll(session)
	check(err)
	var cluster xenapi.ClusterRef
	if len(existing) > 0 {
		cluster = existing[0]
	} else {
		// Corosync must not lose its network, so each host's PIF on it has to refuse unplugging first:
		// Cluster.PoolCreate fails PIF_ALLOWS_UNPLUG otherwise. was remembers the settings to restore.
		for ref := range was {
			check(xenapi.PIF.SetDisallowUnplug(session, ref, true))
		}
		// token_timeout is in seconds (the API's default is 20.0, coefficient 1.0): XS9 refuses 20000 as
		// "too large" - it is not milliseconds.
		cluster, err = xenapi.Cluster.PoolCreate(session, network, "corosync", 20.0, 1.0)
		check(err)
	}

	stack, _ := xenapi.Cluster.GetClusterStack(session, cluster)
	quorate, _ := xenapi.Cluster.GetIsQuorate(session, cluster)
	live, _ := xenapi.Cluster.GetLiveHosts(session, cluster)
	quorum, _ := xenapi.Cluster.GetQuorum(session, cluster)
	fmt.Printf("Stack:      %s\n", stack)
	fmt.Printf("Quorate:    %t (%d/%d needed)\n", quorate, live, quorum)

	// Taking a host out is what a management-interface change does; it can cost quorum.
	members, err := xenapi.ClusterHost.GetAll(session)
	check(err)
	check(xenapi.ClusterHost.Disable(session, members[0]))
	quorate, _ = xenapi.Cluster.GetIsQuorate(session, cluster)
	fmt.Printf("One member out, quorate: %t\n", quorate)

	check(xenapi.ClusterHost.Enable(session, members[0]))
	check(xenapi.Cluster.PoolResync(session, cluster))
	quorate, _ = xenapi.Cluster.GetIsQuorate(session, cluster)
	fmt.Printf("Resynced,   quorate: %t\n", quorate)

	// Tidy up a cluster this example created (one that was already there stays), and the PIF settings.
	if len(existing) == 0 {
		check(xenapi.Cluster.PoolDestroy(session, cluster))
		for ref, v := range was {
			check(xenapi.PIF.SetDisallowUnplug(session, ref, v))
		}
		fmt.Println("Cluster removed again.")
	}

	fmt.Println("OK: configure-clustering")
	session.Logout()
}
```

<details><summary>Sample output</summary>

```text
Stack:      corosync
Quorate:    true (2/2 needed)
One member out, quorate: false
Resynced,   quorate: true
Cluster removed again.
OK: configure-clustering
```

</details>

## PowerShell

Source: [`powershell/HostsAndPools/Invoke-ConfigureClustering.ps1`](../../powershell/HostsAndPools/Invoke-ConfigureClustering.ps1)

```powershell
function Invoke-ConfigureClustering {
    <#
    .SYNOPSIS
        Configure clustering.
    .DESCRIPTION
        Enable the clustering layer that shared block storage needs for thin provisioning, then watch quorum
        as a host leaves the cluster and rejoins it.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password
    )
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password

    # Clustering is what shared block storage needs before GFS2 thin provisioning. Run it over a network
    # every host is on - the management network - since corosync is latency-sensitive and a cluster that
    # loses quorum takes its GFS2 storage offline with it.
    $pifs = @(Get-XenPIF)
    $network = Get-XenNetwork -Ref ($pifs | Where-Object { $_.management } | Select-Object -First 1).network.opaque_ref
    $networkPifs = @($pifs | Where-Object { $_.network.opaque_ref -eq $network.opaque_ref })

    $cluster = Get-XenCluster | Select-Object -First 1
    $created = -not $cluster
    if ($created) {
        # Corosync must not lose its network, so each host's PIF on it has to refuse unplugging first:
        # Cluster.pool_create fails PIF_ALLOWS_UNPLUG otherwise. $networkPifs keeps the old settings.
        $networkPifs | ForEach-Object { Set-XenPIF -Ref $_.opaque_ref -DisallowUnplug $true }
        # Invoke-XenCluster's parameter sets are XenObject / Ref / Uuid -- every one of them identifies an
        # EXISTING cluster -- so the module cannot express pool_create, which is a constructor. Same
        # situation as the event API: call it over JSON-RPC (see Invoke-XenMethod in Helpers.ps1).
        $ref = Invoke-XenMethod -Session $session -Method 'Cluster.pool_create' `
            -Params @($network.opaque_ref, 'corosync', 20.0, 1.0)  # seconds, not ms: XS9 refuses 20000
        $cluster = Get-XenCluster -Ref $ref
    }

    Write-Host "Stack:      $($cluster.cluster_stack)"
    Write-Host "Quorate:    $($cluster.is_quorate) ($($cluster.live_hosts)/$($cluster.quorum) needed)"

    # Taking a host out is what a management-interface change does; it can cost quorum.
    $member = Get-XenClusterHost | Select-Object -First 1
    Invoke-XenClusterHost -Ref $member.opaque_ref -XenAction Disable
    Write-Host "One member out, quorate: $((Get-XenCluster | Select-Object -First 1).is_quorate)"

    Invoke-XenClusterHost -Ref $member.opaque_ref -XenAction Enable
    Invoke-XenCluster -Ref $cluster.opaque_ref -XenAction PoolResync
    Write-Host "Resynced,   quorate: $((Get-XenCluster | Select-Object -First 1).is_quorate)"

    # Tidy up a cluster this example created (one that was already there stays), and the PIF settings.
    if ($created) {
        Invoke-XenCluster -Ref $cluster.opaque_ref -XenAction PoolDestroy
        $networkPifs | ForEach-Object { Set-XenPIF -Ref $_.opaque_ref -DisallowUnplug $_.disallow_unplug }
        Write-Host "Cluster removed again."
    }

    Write-Host "OK: configure-clustering"
    $session | Disconnect-XenServer
}
```

<details><summary>Sample output</summary>

```text
Stack:      corosync
Quorate:    True (2/2 needed)
One member out, quorate: False
Resynced,   quorate: True
Cluster removed again.
OK: configure-clustering
```

</details>

## xe CLI

Source: [`cli/hosts-and-pools/configure-clustering.sh`](../../cli/hosts-and-pools/configure-clustering.sh)

```bash
# Configure clustering.
#
# Enable the clustering layer that shared block storage needs for thin provisioning, then watch quorum as a
# host leaves the cluster and rejoins it.
#
# Run it:
#   ./workflows.sh configure-clustering https://xenserver root "$password"

configure_clustering() {
    local cluster member network created=false pif
    local -A was=()
    # Run corosync over a network every host is on - the management network.
    network=$(first_csv "$(xe pif-list management=true params=network-uuid --minimal)")
    cluster=$(first_csv "$(xe cluster-list --minimal)")
    if [ -z "$cluster" ]; then
        # Corosync must not lose its network, so each host's PIF on it has to refuse unplugging first:
        # cluster-pool-create fails PIF_ALLOWS_UNPLUG otherwise. Remember the settings to restore them.
        for pif in $(each_csv "$(xe pif-list network-uuid="$network" --minimal)"); do
            was[$pif]=$(xe pif-param-get uuid="$pif" param-name=disallow-unplug)
            xe pif-param-set uuid="$pif" disallow-unplug=true
        done
        cluster=$(xe cluster-pool-create network-uuid="$network")
        created=true
    fi

    echo "Stack:      $(xe cluster-list uuid="$cluster" params=cluster-stack --minimal)"
    echo "Quorate:    $(xe cluster-list uuid="$cluster" params=is-quorate --minimal)"

    # Taking a host out is what a management-interface change does; it can cost quorum.
    member=$(first_csv "$(xe cluster-host-list --minimal)")
    xe cluster-host-disable uuid="$member"
    echo "One member out, quorate: $(xe cluster-list uuid="$cluster" params=is-quorate --minimal)"

    xe cluster-host-enable uuid="$member"
    xe cluster-pool-resync cluster-uuid="$cluster"
    echo "Resynced,   quorate: $(xe cluster-list uuid="$cluster" params=is-quorate --minimal)"

    # Tidy up a cluster this example created (one that was already there stays), and the PIF settings.
    if [ "$created" = true ]; then
        xe cluster-pool-destroy cluster-uuid="$cluster"
        for pif in "${!was[@]}"; do xe pif-param-set uuid="$pif" disallow-unplug="${was[$pif]}"; done
        echo "Cluster removed again."
    fi
    echo "OK: configure-clustering"
}
```

<details><summary>Sample output</summary>

```text
Stack:      corosync
Quorate:    true
One member out, quorate: false
Resynced,   quorate: true
Cluster removed again.
OK: configure-clustering
```

</details>
