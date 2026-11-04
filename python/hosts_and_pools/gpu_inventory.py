"""GPU inventory.

Enumerate the pool's GPU groups, their physical GPUs and the vGPU types each offers.

Run it::

    gpu_inventory("https://xenserver", "root", password)
"""

from connection import connect


def gpu_inventory(url, username, password):
    """Take an inventory of the pool's GPU groups: their pGPUs and the vGPU types they support."""
    session = connect(url, username, password)
    groups = session.xenapi.GPU_group.get_all_records()
    print("GPU groups (%d):" % len(groups))
    for group in groups.values():
        types = [session.xenapi.VGPU_type.get_model_name(t) for t in group["supported_VGPU_types"]]
        print("  - %s: %d pGPU(s), vGPU types: %s"
              % (group["name_label"], len(group["PGPUs"]), ", ".join(types)))
    # How the pool spreads vGPUs across the physical GPUs in a group: depth-first packs each pGPU
    # full before using the next, breadth-first spreads them out.
    group_ref = list(groups.keys())[0]
    before = session.xenapi.GPU_group.get_allocation_algorithm(group_ref)
    session.xenapi.GPU_group.set_allocation_algorithm(group_ref, "breadth_first")
    print("Allocation:      %s -> %s"
          % (before, session.xenapi.GPU_group.get_allocation_algorithm(group_ref)))
    session.xenapi.GPU_group.set_allocation_algorithm(group_ref, before)
    print("OK: gpu-inventory")
    session.xenapi.session.logout()
