# PVS Accelerator inventory.
#
# Document a pool's Citrix Provisioning (PVS) Accelerator setup: each site's read cache (host, size, storage),
# its PVS servers (addresses and streaming port range), and which VMs are accelerated versus the whole pool.
#
# Run it:
#   ./workflows.sh pvs-accelerator https://xenserver root "$password"

pvs_accelerator() {
    sites=$(xe pvs-site-list --minimal)
    if [ -z "$sites" ]; then echo "No PVS Accelerator sites are configured."; echo "OK: pvs-accelerator"; return; fi
    for site in ${sites//,/ }; do
        echo "Site: $(xe pvs-site-param-get uuid=$site param-name=name-label)"
        cslist=$(xe pvs-cache-storage-list --minimal)
        for cs in ${cslist//,/ }; do
            h=$(xe pvs-cache-storage-param-get uuid=$cs param-name=host-uuid)
            sr=$(xe pvs-cache-storage-param-get uuid=$cs param-name=sr-uuid)
            size=$(xe pvs-cache-storage-param-get uuid=$cs param-name=size)
            echo "  cache:  $(xe host-param-get uuid=$h param-name=name-label)  $((size / 1024 / 1024 / 1024)) GiB on $(xe sr-param-get uuid=$sr param-name=name-label)"
        done
        srvlist=$(xe pvs-server-list --minimal)
        for srv in ${srvlist//,/ }; do
            echo "  server: $(xe pvs-server-param-get uuid=$srv param-name=addresses)  ports $(xe pvs-server-param-get uuid=$srv param-name=first-port)-$(xe pvs-server-param-get uuid=$srv param-name=last-port)"
        done
        # One proxy accelerates one VM in this pool, so proxy count = accelerated VM count.
        accelerated=$(count_csv "$(xe pvs-proxy-list --minimal)")
        total=$(count_csv "$(xe vm-list is-control-domain=false --minimal)")
        echo "  $accelerated of $total VM(s) accelerated"
    done
    echo "OK: pvs-accelerator"
}
