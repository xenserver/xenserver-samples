# Create an NFS SR.
#
# Create a shared NFS storage repository on an NFS export (nfs_server, nfs_path), then detach and forget it.
#
# Run it:
#   ./workflows.sh create-nfs-sr https://xenserver root "$password"
#
# Optional key=value arguments (default):
#   nfs_server (192.0.2.10)
#   nfs_path (/export/sdk)

create_nfs_sr() {
    local nfs_server nfs_path
    nfs_server=$(param nfs_server "192.0.2.10")
    nfs_path=$(param nfs_path "/export/sdk")
    sr=$(xe sr-create host-uuid=$(first_host) type=nfs name-label=xe-example-nfs \
        device-config:server="$nfs_server" device-config:serverpath="$nfs_path" device-config:nfsversion=3 shared=true)
    echo "Created SR: $sr"
    detach_and_forget_sr $sr
    echo "OK: create-nfs-sr"
}
