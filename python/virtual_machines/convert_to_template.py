"""Convert a VM to a template.

Turn a VM into a reusable custom template. This is a one-way operation.

Run it::

    convert_to_template("https://xenserver", "root", password, "Rocky Linux 8")
"""

from connection import connect
from helpers import destroy_vm_and_disks, provision, template_by_name


def convert_to_template(url, username, password, template_name, new_vm_name="sdk-example-totemplate"):
    """Provision a real VM, convert it into a custom template, then destroy it."""
    session = connect(url, username, password)
    vm = session.xenapi.VM.clone(template_by_name(session, template_name), new_vm_name)
    provision(session, vm)  # now a real (halted) VM
    print("is_a_template after provision: %s" % session.xenapi.VM.get_is_a_template(vm))

    # Converting a VM to a custom template is a one-way operation.
    session.xenapi.VM.set_is_a_template(vm, True)
    print("is_a_template after convert:  %s" % session.xenapi.VM.get_is_a_template(vm))

    destroy_vm_and_disks(session, vm)
    print("OK: convert-to-template")
    session.xenapi.session.logout()
