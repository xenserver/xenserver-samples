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
    network=$(first_csv "$(remote_xe pif-list management=true params=network-uuid --minimal)")
    cluster=$(first_csv "$(remote_xe cluster-list --minimal)")
    if [ -z "$cluster" ]; then
        # Corosync must not lose its network, so each host's PIF on it has to refuse unplugging first:
        # cluster-pool-create fails PIF_ALLOWS_UNPLUG otherwise. Remember the settings to restore them.
        for pif in $(each_csv "$(remote_xe pif-list network-uuid="$network" --minimal)"); do
            was[$pif]=$(remote_xe pif-param-get uuid="$pif" param-name=disallow-unplug)
            remote_xe pif-param-set uuid="$pif" disallow-unplug=true
        done
        cluster=$(remote_xe cluster-pool-create network-uuid="$network")
        created=true
    fi

    echo "Stack:      $(remote_xe cluster-list uuid="$cluster" params=cluster-stack --minimal)"
    echo "Quorate:    $(remote_xe cluster-list uuid="$cluster" params=is-quorate --minimal)"

    # Taking a host out is what a management-interface change does; it can cost quorum.
    member=$(first_csv "$(remote_xe cluster-host-list --minimal)")
    remote_xe cluster-host-disable uuid="$member"
    echo "One member out, quorate: $(remote_xe cluster-list uuid="$cluster" params=is-quorate --minimal)"

    remote_xe cluster-host-enable uuid="$member"
    remote_xe cluster-pool-resync cluster-uuid="$cluster"
    echo "Resynced,   quorate: $(remote_xe cluster-list uuid="$cluster" params=is-quorate --minimal)"

    # Tidy up a cluster this example created (one that was already there stays), and the PIF settings.
    if [ "$created" = true ]; then
        remote_xe cluster-pool-destroy cluster-uuid="$cluster"
        for pif in "${!was[@]}"; do remote_xe pif-param-set uuid="$pif" disallow-unplug="${was[$pif]}"; done
        echo "Cluster removed again."
    fi
    ok configure-clustering
}
