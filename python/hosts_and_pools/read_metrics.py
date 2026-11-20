"""Read host & VM metrics.

Read live host metrics (total/free memory, liveness) and VM metrics (vCPU count, memory).

Run it::

    read_metrics("https://xenserver", "root", password)
"""

from connection import connect


def read_metrics(url, username, password):
    """Read live capacity metrics off a host and a running VM (Host_metrics / VM_metrics)."""
    MIB = 1024 * 1024
    session = connect(url, username, password)
    host_ref, host = next(iter(session.xenapi.host.get_all_records().items()))
    hm = session.xenapi.host.get_metrics(host_ref)
    print("Host %s: %d MiB total, %d MiB free, live = %s"
          % (host["name_label"],
             int(session.xenapi.host_metrics.get_memory_total(hm)) // MIB,
             int(session.xenapi.host.compute_free_memory(host_ref)) // MIB,
             session.xenapi.host_metrics.get_live(hm)))

    vm = next(ref for ref, r in session.xenapi.VM.get_all_records().items()
              if not r["is_a_template"] and not r["is_control_domain"]
              and r["power_state"] == "Running")
    vmm = session.xenapi.VM.get_metrics(vm)
    print("VM %s: %s vCPU(s), %d MiB"
          % (session.xenapi.VM.get_name_label(vm),
             session.xenapi.VM_metrics.get_VCPUs_number(vmm),
             int(session.xenapi.VM_metrics.get_memory_actual(vmm)) // MIB))
    print("OK: read-metrics")
    session.xenapi.session.logout()
