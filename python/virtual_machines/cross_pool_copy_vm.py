"""Cross-pool copy a VM.

Copy a VM from one pool to another: open a session to each pool, obtain a receiver token on the
destination, then send a copy of the VM from the source. Takes the destination pool's URL as an
extra argument after the password.

Run it::

    cross_pool_copy_vm("https://poolA", "root", password, "https://poolB")
"""

from connection import connect
from helpers import destroy_vm_and_disks, vm_by_name


def cross_pool_copy_vm(url, username, password, dest_url, vm_name="db-01",
                       dest_username=None, dest_password=None):
    """Copy a VM from one pool to another (Storage XenMotion copy): get a receiver token from the
    destination with host.migrate_receive, then VM.migrate_send with copy=true on the source."""
    source = connect(url, username, password)
    dest = connect(dest_url, dest_username or username, dest_password or password)
    # Destination: choose a host, network and SR, then ask for a receiver token. The disks go to
    # the destination pool's default SR and the data travels over the host's management network -
    # one both pools can certainly reach (the first network listed may well not be).
    dest_pool = dest.xenapi.pool.get_all()[0]
    dest_host = dest.xenapi.pool.get_master(dest_pool)
    dest_sr = dest.xenapi.pool.get_default_SR(dest_pool)
    dest_network = next(dest.xenapi.PIF.get_network(pif) for pif in dest.xenapi.host.get_PIFs(dest_host)
                        if dest.xenapi.PIF.get_management(pif))
    receiver = dest.xenapi.host.migrate_receive(dest_host, dest_network, {})

    # Source: map every disk to the destination SR and every NIC to the destination network,
    # then send with copy=true (source VM is left intact).
    vm = vm_by_name(source, vm_name)
    vdi_map = {}
    for vbd in source.xenapi.VM.get_VBDs(vm):
        if source.xenapi.VBD.get_type(vbd) != "Disk":
            continue
        vdi = source.xenapi.VBD.get_VDI(vbd)
        if vdi != "OpaqueRef:NULL":
            vdi_map[vdi] = dest_sr
    vif_map = {vif: dest_network for vif in source.xenapi.VM.get_VIFs(vm)}

    copy = source.xenapi.VM.migrate_send(vm, receiver, False, vdi_map, vif_map, {"copy": "true"}, {})
    print("Sent '%s' to the destination pool (copy); source still present: %s"
          % (vm_name, vm_by_name(source, vm_name) == vm))
    # The result is the new VM's ref on the DESTINATION pool - use the destination session to read it.
    print("  the copy on the destination: %s (%s)"
          % (dest.xenapi.VM.get_name_label(copy), dest.xenapi.VM.get_uuid(copy)))

    # Tidy up so the example is repeatable: the copy and its disks, on the destination pool.
    destroy_vm_and_disks(dest, copy)
    print("OK: cross-pool-copy-vm")
    source.xenapi.session.logout()
    dest.xenapi.session.logout()
