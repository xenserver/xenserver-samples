"""Manage network interfaces.

Attach a virtual network interface to a VM and remove it again.

Run it::

    manage_vif("https://xenserver", "root", password, "Rocky Linux 8")
"""

from connection import connect
from helpers import destroy_vm_and_disks, provision, template_by_name


def manage_vif(url, username, password, template_name, new_vm_name="sdk-example-vif"):
    """Provision a throwaway VM, attach a VIF to the first network, then tear it all down."""
    session = connect(url, username, password)
    vm = session.xenapi.VM.clone(template_by_name(session, template_name), new_vm_name)
    provision(session, vm)
    net_ref = session.xenapi.network.get_all()[0]
    device = session.xenapi.VM.get_allowed_VIF_devices(vm)[0]

    vif = session.xenapi.VIF.create({
        "VM": vm, "network": net_ref, "device": device, "MAC": "",
        "MTU": "1500", "other_config": {},
        "qos_algorithm_type": "", "qos_algorithm_params": {},
    })
    print("Attached a VIF on device %s; VM now has %d NIC(s)"
          % (device, len(session.xenapi.VM.get_VIFs(vm))))

    session.xenapi.VIF.destroy(vif)
    destroy_vm_and_disks(session, vm)
    print("OK: manage-vif")
    session.xenapi.session.logout()
