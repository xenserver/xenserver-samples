"""PVS Accelerator inventory.

Document a pool's Citrix Provisioning (PVS) Accelerator setup: each site's read cache (host, size,
storage), its PVS servers (addresses and streaming port range), and which VMs are accelerated versus
the whole pool.
"""

from connection import connect


# Maps the <workflow> argument to the matching self-contained function above, supplying the
# concrete objects each one operates on. In your own scripts you would call these functions
# directly (see the "Run it:" line under each) rather than through this dispatcher.
def pvs_accelerator(url, username, password):
    session = connect(url, username, password)
    x = session.xenapi
    sites = x.PVS_site.get_all_records()
    if not sites:
        print("No PVS Accelerator sites are configured.")
    for site in sites.values():
        print("Site: %s" % site["name_label"])
        for cs_ref in site["cache_storage"]:
            cs = x.PVS_cache_storage.get_record(cs_ref)
            host = x.host.get_record(cs["host"])
            sr = x.SR.get_record(cs["SR"])
            print("  cache:  %s  %d GiB on %s" % (host["name_label"], int(cs["size"]) // (1024 ** 3), sr["name_label"]))
        for server_ref in site["servers"]:
            server = x.PVS_server.get_record(server_ref)
            print("  server: %s  ports %s-%s" % (", ".join(server["addresses"]), server["first_port"], server["last_port"]))
        # Which VMs are accelerated: walk each proxy to its VIF to its VM.
        accelerated = {}
        for proxy_ref in site["proxies"]:
            proxy = x.PVS_proxy.get_record(proxy_ref)
            vif = x.VIF.get_record(proxy["VIF"])
            accelerated[vif["VM"]] = proxy["status"]
        guests = [(ref, v) for ref, v in x.VM.get_all_records().items()
                  if not v["is_control_domain"] and not v["is_a_template"] and not v["is_a_snapshot"]]
        count = sum(1 for ref, _ in guests if ref in accelerated)
        print("  %d of %d VM(s) accelerated" % (count, len(guests)))
    print("OK: pvs-accelerator")
    session.logout()
