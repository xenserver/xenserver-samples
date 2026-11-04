# Detach, reattach and forget storage.
#
# Take a storage repository offline and bring it back: disconnect it from every host, reconnect and rescan it,
# then disconnect it once more and forget it for good.
#
# Run it:
#   ./workflows.sh manage-sr-lifecycle https://xenserver root "$password"
#
# Optional key=value arguments (default):
#   nfs_server (192.0.2.10)
#   nfs_path (/export/spare)

manage_sr_lifecycle() {
    sr=$(xe sr-create name-label=xe-example-lifecycle type=nfs content-type=user shared=true \
        device-config:server="$(param nfs_server 192.0.2.10)" \
        device-config:serverpath="$(param nfs_path /export/spare)" device-config:nfsversion=3)

    # There is no sr-detach: a shared SR is joined to each host by one PBD, and detaching the SR means
    # unplugging every one of them. That is why an SR can be attached on some hosts and not others.
    pbds=$(xe pbd-list sr-uuid=$sr --minimal)
    echo "$(xe sr-param-get uuid=$sr param-name=name-label): connected on $(count_attached_pbd "$pbds") of $(count_csv "$pbds") host(s)"

    for pbd in $(each_csv "$pbds"); do xe pbd-unplug uuid=$pbd; done
    echo "  detached:   connected on $(count_attached_pbd "$pbds") host(s)"

    # Plugging them back is exactly what a repair does.
    for pbd in $(each_csv "$pbds"); do xe pbd-plug uuid=$pbd; done
    echo "  reattached: connected on $(count_attached_pbd "$pbds") host(s)"

    xe sr-scan uuid=$sr
    echo "  rescanned:  $(count_csv "$(xe vdi-list sr-uuid=$sr --minimal)") disk(s)"

    # Forgetting drops the pool's record of the SR but leaves the storage itself untouched, so the same
    # export can be introduced again later. Detach before forgetting: a connected SR is still in use.
    for pbd in $(each_csv "$pbds"); do xe pbd-unplug uuid=$pbd; done
    xe sr-forget uuid=$sr
    echo "  forgotten"
    echo "OK: manage-sr-lifecycle"
}

# How many of the given PBDs are currently attached.
count_attached_pbd() {
    local n=0
    for pbd in $(each_csv "$1"); do
        if [ "$(xe pbd-param-get uuid=$pbd param-name=currently-attached)" = "true" ]; then n=$((n + 1)); fi
    done
    echo $n
}
