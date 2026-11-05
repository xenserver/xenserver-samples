# Configure PVS Accelerator.
#
# Build a PVS Accelerator site from nothing and take it down again: introduce the site and a PVS server, put a
# read cache on each host's local storage, accelerate a VM by proxying its first NIC, then forget the site —
# which cascades to everything hanging off it.
#
# Run it:
#   ./workflows.sh configure-pvs-accelerator https://xenserver root "$password"
#
# Optional key=value arguments (default):
#   vm_name (db-01)

configure_pvs_accelerator() {
    local vm_name vm vif
    vm_name=$(param vm_name "db-01")
    # Check the VM first, before creating anything: it needs a NIC for the proxy to sit on, and one that
    # no site accelerates yet (a VIF takes one proxy: PVS_PROXY_ALREADY_PRESENT). It need not be running
    # - a proxy on a halted VM just reports "stopped" until it starts.
    vm=$(vm_uuid "$vm_name")
    name=$(xe vm-param-get uuid=$vm param-name=name-label)
    vif=$(lowest_device_vif "$vm")
    if [ -z "$vif" ]; then
        echo "$vm_name has no network interface to accelerate" >&2
        return 1
    fi
    existing=$(xe pvs-proxy-list vif-uuid=$vif --minimal)
    if [ -n "$existing" ]; then
        existing_site=$(xe pvs-proxy-param-get uuid=$existing param-name=site-uuid)
        echo "$vm_name is already accelerated by site '$(xe pvs-site-param-get uuid=$existing_site param-name=name-label)'" >&2
        return 1
    fi

    site=$(xe pvs-site-introduce name-label=sdk-example-pvs name-description="Created by the SDK examples")
    xe pvs-server-introduce addresses=203.0.113.90 first-port=6910 last-port=6930 pvs-site-uuid="$site" >/dev/null

    # The read cache should be on LOCAL storage: keeping reads off the network is the point, and the
    # server does not enforce that, but a cache on shared storage rarely makes sense and can't be
    # shared between hosts anyway.
    for h in $(each_csv "$(xe host-list --minimal)"); do
        for pbd in $(each_csv "$(xe pbd-list host-uuid=$h --minimal)"); do
            sr=$(xe pbd-param-get uuid=$pbd param-name=sr-uuid)
            [ "$(xe sr-param-get uuid=$sr param-name=shared)" = "false" ] || continue
            [ "$(xe sr-param-get uuid=$sr param-name=content-type)" = "iso" ] && continue
            [ "$(xe sr-param-get uuid=$sr param-name=type)" = "udev" ] && continue   # removable storage
            xe pvs-cache-storage-create uuid=$h sr-uuid=$sr pvs-site-uuid="$site" size=10737418240 >/dev/null
            break
        done
    done

    # A proxy may only sit on the VM's LOWEST-numbered NIC, hence sorting by device above rather than
    # just taking the first VIF listed — the list comes back in creation order, which is the same thing
    # only by luck.
    proxy=$(xe pvs-proxy-create pvs-site-uuid="$site" vif-uuid="$vif")

    # Scoped to THIS site: the pool may already have one, and counting pool-wide would report its
    # caches and servers as though this example had made them.
    caches=$(count_csv "$(xe pvs-cache-storage-list pvs-site-uuid="$site" --minimal)")
    servers=$(count_csv "$(xe pvs-server-list pvs-site-uuid="$site" --minimal)")
    echo "Site '$(xe pvs-site-param-get uuid=$site param-name=name-label)' with $caches cache(s) and $servers server(s)"
    # "caching" means it is really accelerating: a site with no cache reports "initialised", and a
    # proxy on a VM whose NIC is unplugged reports "stopped".
    echo "  $name: $(xe pvs-proxy-param-get uuid=$proxy param-name=status)"

    # Forgetting the site only cascades its cache storage - a running proxy or a server it still has makes
    # forget refuse with PVS_SITE_CONTAINS_RUNNING_PROXIES/_SERVERS, so tear those down first, in the same
    # order every real PVS teardown uses.
    xe pvs-proxy-destroy uuid="$proxy"
    for srv in $(each_csv "$(xe pvs-server-list pvs-site-uuid="$site" --minimal)"); do
        xe pvs-server-forget uuid="$srv"
    done
    xe pvs-site-forget uuid="$site"
    echo "OK: configure-pvs-accelerator"
}

# The VIF with the lowest device number on a VM. (vif-list --minimal prints only uuids even when params=
# names more fields, so each VIF's device is read on its own.)
lowest_device_vif() {
    local vif dev best_uuid="" best_dev=""
    for vif in $(each_csv "$(xe vif-list vm-uuid=$1 --minimal)"); do
        dev=$(xe vif-param-get uuid=$vif param-name=device)
        if [ -z "$best_dev" ] || [ "$dev" -lt "$best_dev" ]; then best_uuid=$vif; best_dev=$dev; fi
    done
    echo "$best_uuid"
}
