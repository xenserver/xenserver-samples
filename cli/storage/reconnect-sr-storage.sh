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
