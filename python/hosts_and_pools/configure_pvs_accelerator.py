"""Configure PVS Accelerator.

Build a PVS Accelerator site from nothing and take it down again: introduce the site and a PVS
server, put a read cache on each host's local storage, accelerate a VM by proxying its first NIC,
then forget the site — which cascades to everything hanging off it.
"""

from connection import connect
from helpers import vm_by_name


def configure_pvs_accelerator(url, username, password, vm_name):
    """Build a PVS Accelerator site from nothing: a site, a PVS server, a read cache on each
    host, and one accelerated VM (vm_name). Then take it all down again.

    The inventory example above reads a configuration someone else made; this one makes it."""
    session = connect(url, username, password)
    x = session.xenapi

    # Check the VM first, before creating anything: it needs a NIC for the proxy to sit on, and one
    # that no site accelerates yet (a VIF takes one proxy: PVS_PROXY_ALREADY_PRESENT). It need not be
    # running - a proxy on a halted VM just reports "stopped" until it starts.
    vm = vm_by_name(session, vm_name)
    vifs = sorted(x.VM.get_VIFs(vm), key=lambda v: int(x.VIF.get_device(v)))
    if not vifs:
        raise RuntimeError("%s has no network interface to accelerate" % vm_name)
    for proxy in x.PVS_proxy.get_all_records().values():
        if proxy["VIF"] == vifs[0]:
            raise RuntimeError("%s is already accelerated by site '%s'"
                               % (vm_name, x.PVS_site.get_name_label(proxy["site"])))

    site = x.PVS_site.introduce("sdk-example-pvs", "Created by the SDK examples", "")
    x.PVS_server.introduce(["203.0.113.90"], 6910, 6930, site)

    # The read cache must be on LOCAL storage. The point of the accelerator is to keep reads off
    # the network, so a cache on a shared SR would defeat it and xapi rejects one.
    for host in x.host.get_all():
        local = local_sr(x, host)
        if local:
            # size as a STRING: XML-RPC only carries 32-bit integers, so the Python binding passes
            # every XenAPI Int as a string. 10 GiB does not fit, and passing an int raises inside
            # xmlrpc.client rather than at the API — a confusing place to land.
            x.PVS_cache_storage.create({"host": host, "SR": local, "site": site,
                                        "size": str(10 * 1024 ** 3)})

    # A proxy may only sit on the VM's LOWEST-numbered VIF, hence sorting by device above rather than
    # taking VIFs[0] — the list comes back in creation order, which is the same thing only by luck.
    proxy = x.PVS_proxy.create(site, vifs[0])

    print("Site '%s' with %d cache(s) and %d server(s)"
          % (x.PVS_site.get_name_label(site),
             len(x.PVS_site.get_cache_storage(site)),
             len(x.PVS_site.get_servers(site))))
    # "caching" means it is actually accelerating. A site with no cache storage reports
    # "initialised", and a proxy on a VM whose VIF is unplugged reports "stopped".
    print("  %s: %s" % (x.VM.get_name_label(vm), x.PVS_proxy.get_status(proxy)))

    # Forgetting the site only cascades its cache storage - a running proxy or a server it still
    # has makes forget refuse with PVS_SITE_CONTAINS_RUNNING_PROXIES/_SERVERS, so tear those down
    # ourselves first, in the same order every real PVS teardown uses.
    x.PVS_proxy.destroy(proxy)
    for server_ref in x.PVS_site.get_servers(site):
        x.PVS_server.forget(server_ref)
    x.PVS_site.forget(site)
    print("OK: configure-pvs-accelerator")
    session.logout()


def local_sr(x, host):
    """The host's own non-ISO storage, found through its PBDs."""
    for pbd in x.host.get_PBDs(host):
        sr = x.PBD.get_SR(pbd)
        record = x.SR.get_record(sr)
        if not record["shared"] and record["content_type"] != "iso" and record["type"] != "udev":
            return sr
    return None
