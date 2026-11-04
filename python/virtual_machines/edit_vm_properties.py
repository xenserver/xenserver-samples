"""Edit VM properties.

Change a VM's description and custom metadata, then read the changes back.

Run it::

    edit_vm_properties("https://xenserver", "root", password, "web-01")
"""

from connection import connect
from helpers import vm_by_name


def edit_vm_properties(url, username, password, vm_name):
    """Edit the named VM's description and other_config, then restore the originals."""
    session = connect(url, username, password)
    vm_ref = vm_by_name(session, vm_name)

    original_desc = session.xenapi.VM.get_name_description(vm_ref)
    session.xenapi.VM.set_name_description(vm_ref, "Edited by the SDK example")
    session.xenapi.VM.add_to_other_config(vm_ref, "sdk_example", "true")
    print("New description: %s" % session.xenapi.VM.get_name_description(vm_ref))
    print("other_config[sdk_example] = %s" %
          session.xenapi.VM.get_other_config(vm_ref).get("sdk_example"))

    # Restore original state.
    session.xenapi.VM.set_name_description(vm_ref, original_desc)
    session.xenapi.VM.remove_from_other_config(vm_ref, "sdk_example")
    print("OK: edit-vm-properties")
    session.xenapi.session.logout()
