# Configure disaster recovery.
#
# Turn on pool metadata replication: the pool writes its database - the configuration of its VMs and vApps
# - to a disk on an iSCSI or Fibre Channel SR, as XenCenter's Configure DR dialog does. Have your storage
# array replicate that SR, and the VMs' SRs, to the disaster recovery site; a pool there can then recover
# the VMs from the replica (see disaster-recovery-failover).
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

    # The pool's own metadata disk on this SR is what says replication is on (as the Configure DR dialog
    # decides): a disk of type metadata whose metadata-of-pool is this pool. xe shows the type as
    # "Metadata", so compare it case-insensitively.
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
