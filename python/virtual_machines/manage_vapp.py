"""Manage a vApp.

Group VMs into an appliance that starts and stops together in a defined order, start and shut it
down as a unit, then remove it.

Run it::

    manage_vapp("https://xenserver", "root", password, "db-01")
"""

from connection import connect
from helpers import NULL_REF


def manage_vapp(url, username, password, vm_name):
    """Group VMs into an appliance that starts and stops together, then remove it."""
    session = connect(url, username, password)
    x = session.xenapi
    vm = x.VM.get_by_name_label(vm_name)[0]

    vapp = x.VM_appliance.create({
        "name_label": "sdk-example-vapp",
        "name_description": "Created by the SDK example",
    })

    # `order` decides the sequence: ascending to start, descending to shut down. That ordering is the
    # reason to use a vApp at all rather than selecting several VMs.
    x.VM.set_appliance(vm, vapp)
    x.VM.set_order(vm, "0")
    x.VM.set_start_delay(vm, "5")

    x.VM_appliance.start(vapp, False)
    print(f"Started:        {x.VM.get_power_state(vm)}")

    # shutdown tries each VM's clean shutdown and falls back to a hard one. clean_shutdown alone fails
    # OPERATION_PARTIALLY_FAILED if any member can't shut down cleanly (no guest OS or PV drivers).
    x.VM_appliance.shutdown(vapp)
    print(f"Shut down:      {x.VM.get_power_state(vm)}")

    x.VM.set_appliance(vm, NULL_REF)
    x.VM_appliance.destroy(vapp)
    print("OK: manage-vapp")
    x.session.logout()
