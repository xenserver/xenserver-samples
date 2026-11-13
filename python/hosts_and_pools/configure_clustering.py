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
