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
