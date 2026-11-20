"""Create a VM from a template.

Clone one of the built-in templates and provision the clone into a real, installable VM.

Run it::

    create_vm("https://xenserver", "root", password, "Rocky Linux 8")
"""

from connection import connect
from helpers import destroy_vm_and_disks, provision, template_by_name


def create_vm(url, username, password, template_name, new_vm_name="sdk-example-vm"):
    """Clone the named template and provision it into a real, installable VM."""
    session = connect(url, username, password)
    template_ref = template_by_name(session, template_name)
    print("Using template: %s" % session.xenapi.VM.get_name_label(template_ref))

    vm_ref = session.xenapi.VM.clone(template_ref, new_vm_name)
    print("Cloned new VM: %s" % session.xenapi.VM.get_uuid(vm_ref))

    # provision() turns the template clone into a normal (installable) VM.
    provision(session, vm_ref)
    print("Provisioned. is_a_template = %s" % session.xenapi.VM.get_is_a_template(vm_ref))

    # Tidy up so the example is repeatable.
    destroy_vm_and_disks(session, vm_ref)
    print("Cleaned up the example VM.")

    print("OK: create-vm")
    session.xenapi.session.logout()
