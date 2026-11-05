"""Create a VM with a vGPU.

Provision a VM from a template and assign it a virtual GPU: find a GPU group that offers a vGPU
type, attach it, and read the assignment back.

Run it::

    create_vm_with_vgpu("https://xenserver", "root", password, "Rocky Linux 8")
"""

from connection import connect
from helpers import destroy_vm_and_disks, provision, template_by_name


def create_vm_with_vgpu(url, username, password, template_name, new_vm_name="sdk-example-vgpu-vm"):
    """Provision a VM from a template and assign it a virtual GPU (VGPU.create)."""
    session = connect(url, username, password)
    # Find a GPU group that offers a real (non-passthrough) vGPU type, plus that type.
    group_ref, vgpu_type_ref = gpu_group_with_vgpu_type(session)
    type_rec = session.xenapi.VGPU_type.get_record(vgpu_type_ref)
    print("Using vGPU type: %s (%d MB framebuffer)"
          % (type_rec["model_name"], int(type_rec["framebuffer_size"]) // (1024 * 1024)))

    # Provision a fresh VM from the template to attach the vGPU to.
    template_ref = template_by_name(session, template_name)
    vm_ref = session.xenapi.VM.clone(template_ref, new_vm_name)
    provision(session, vm_ref)

    # Assign the vGPU: device "0" is the VM's first vGPU slot, other_config is empty.
    vgpu_ref = session.xenapi.VGPU.create(vm_ref, group_ref, "0", {}, vgpu_type_ref)
    print("Created vGPU: %s" % session.xenapi.VGPU.get_uuid(vgpu_ref))

    # Read the assignment back.
    vgpus = session.xenapi.VM.get_VGPUs(vm_ref)
    assigned = session.xenapi.VGPU_type.get_model_name(session.xenapi.VGPU.get_type(vgpus[0]))
    print("VM now has %d vGPU(s); type = %s" % (len(vgpus), assigned))

    # Tidy up so the example is repeatable.
    session.xenapi.VGPU.destroy(vgpu_ref)
    destroy_vm_and_disks(session, vm_ref)
    print("Cleaned up the example VM and its vGPU.")
    print("OK: create-vm-with-vgpu")
    session.xenapi.session.logout()


def gpu_group_with_vgpu_type(session):
    """Find a (GPU_group, VGPU_type) pair where the group offers a non-passthrough vGPU type."""
    for group, r in session.xenapi.GPU_group.get_all_records().items():
        if not r["PGPUs"]:
            continue
        for type_ref in r["supported_VGPU_types"]:
            if session.xenapi.VGPU_type.get_model_name(type_ref) != "passthrough":
                return group, type_ref
    raise RuntimeError("no GPU group offers a vGPU type")
