"""Manage a virtual TPM.

Attach a virtual TPM to a halted VM, read it back and remove it again. A VM may have at most one,
and only while it is halted.

Run it::

    manage_vtpm("https://xenserver", "root", password)
"""

from connection import connect


def manage_vtpm(url, username, password):
    """Attach a virtual TPM to a halted VM, read it back, then remove it.

    A VM may have at most one, and it can only be attached while the VM is Halted — the
    device is presented at boot. XenCenter additionally only offers this for a UEFI guest,
    since that is what a vTPM is for; the API itself does not insist."""
    session = connect(url, username, password)
    x = session.xenapi

    vm = next(ref for ref, v in x.VM.get_all_records().items()
              if not v["is_a_template"] and not v["is_control_domain"]
              and not v["is_a_snapshot"] and v["power_state"] == "Halted"
              and not v["VTPMs"])
    print("Attaching a vTPM to %s" % x.VM.get_name_label(vm))

    vtpm = x.VTPM.create(vm, False)   # is_unique=False: the vTPM may be copied with the VM
    record = x.VTPM.get_record(vtpm)
    print("  persistence backend: %s" % record["persistence_backend"])
    print("  unique to this VM:   %s" % record["is_unique"])
    print("  VM now has %d vTPM(s)" % len(x.VM.get_VTPMs(vm)))

    # The VM advertises whether another can be added; once it has one, it cannot.
    print("  can add another:     %s" % ("create_vtpm" in x.VM.get_allowed_operations(vm)))

    x.VTPM.destroy(vtpm)
    print("  after removal:       %d vTPM(s)" % len(x.VM.get_VTPMs(vm)))
    print("OK: manage-vtpm")
    session.logout()
