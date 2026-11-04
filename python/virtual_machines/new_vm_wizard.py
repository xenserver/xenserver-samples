"""Create a VM (full workflow).

Create a VM end to end: pick a template, name the VM, choose an installation source and a home
server, set CPU & memory, add a disk on a storage repository, attach a network interface and start
it — the full sequence, rather than a single clone call.

Run it::

    new_vm_wizard("https://xenserver", "root", password, "Rocky Linux 8")
"""

from connection import connect
from helpers import template_by_name


def new_vm_wizard(url, username, password, template_name, new_vm_name="wizard-vm"):
    """
    Reproduce XenCenter's New VM wizard end to end: start from the named template, name the VM,
    choose an installation source, a home server, CPU & memory, add a disk, attach a network,
    then start it.
    """
    GIB = 1024 * 1024 * 1024
    MIB = 1024 * 1024

    session = connect(url, username, password)
    # Page 1 - Template.
    template_ref = template_by_name(session, template_name)
    print("Template:      %s" % session.xenapi.VM.get_name_label(template_ref))

    # Page 2 - Name and description.
    vm = session.xenapi.VM.clone(template_ref, new_vm_name)
    session.xenapi.VM.set_name_description(vm, "Created by the full New VM wizard example")
    session.xenapi.VM.set_is_a_template(vm, False)
    print("Created VM:    %s" % session.xenapi.VM.get_uuid(vm))

    # Page 3 - Installation media (a network install repository).
    session.xenapi.VM.add_to_other_config(vm, "install-repository",
                                          "http://mirror.example.com/rocky/9/os/x86_64")
    print("Install media: network repository")

    # Page 4 - Home server (affinity).
    host_ref, host = next(iter(session.xenapi.host.get_all_records().items()))
    session.xenapi.VM.set_affinity(vm, host_ref)
    print("Home server:   %s" % host["name_label"])

    # Page 5 - CPU & Memory (memory sizes are passed as strings: they exceed XML-RPC's 32-bit int).
    session.xenapi.VM.set_VCPUs_max(vm, "2")
    session.xenapi.VM.set_VCPUs_at_startup(vm, "2")
    session.xenapi.VM.set_memory_limits(vm, str(512 * MIB), str(2 * GIB), str(2 * GIB), str(2 * GIB))
    print("CPU/memory:    2 vCPUs, 2 GiB")

    # Page 6 - Storage: add a disk on a (non-ISO) SR.
    sr_ref = next(ref for ref, r in session.xenapi.SR.get_all_records().items()
                  if r["content_type"] != "iso" and r["type"] not in ("iso", "udev"))
    vbd_device = session.xenapi.VM.get_allowed_VBD_devices(vm)[0]
    vdi = session.xenapi.VDI.create({
        "name_label": "%s disk 0" % new_vm_name,
        "name_description": "System disk created by the wizard example",
        "SR": sr_ref,
        "virtual_size": str(24 * GIB),
        "type": "system",
        "sharable": False,
        "read_only": False,
        "other_config": {},
    })
    session.xenapi.VBD.create({
        "VM": vm, "VDI": vdi, "userdevice": vbd_device, "bootable": True,
        "mode": "RW", "type": "Disk", "empty": False, "other_config": {},
        "qos_algorithm_type": "", "qos_algorithm_params": {},
    })
    print("Storage:       24 GiB disk on %s" % session.xenapi.SR.get_name_label(sr_ref))

    # Page 7 - Networking: attach a VIF to a network.
    net_ref, net = next(iter(session.xenapi.network.get_all_records().items()))
    vif_device = session.xenapi.VM.get_allowed_VIF_devices(vm)[0]
    session.xenapi.VIF.create({
        "VM": vm, "network": net_ref, "device": vif_device, "MAC": "",
        "MTU": "1500", "other_config": {},
        "qos_algorithm_type": "", "qos_algorithm_params": {},
    })
    print("Networking:    NIC on %s" % net["name_label"])

    # Page 8 - Finish: start the VM.
    session.xenapi.VM.start(vm, False, True)

    # Report the assembled VM.
    print("--- Result ---")
    print("power state:   %s" % session.xenapi.VM.get_power_state(vm))
    print("vCPUs:         %s" % session.xenapi.VM.get_VCPUs_max(vm))
    print("disks:         %d, NICs: %d" %
          (len(session.xenapi.VM.get_VBDs(vm)), len(session.xenapi.VM.get_VIFs(vm))))

    # Tidy up so the example is repeatable.
    session.xenapi.VM.hard_shutdown(vm)
    session.xenapi.VM.destroy(vm)
    session.xenapi.VDI.destroy(vdi)
    print("Cleaned up the example VM.")

    print("OK: new-vm-wizard")
    session.xenapi.session.logout()
