"""Custom fields.

Attach and read custom name/value fields on a VM — arbitrary metadata you define, stored on the
object.

Run it::

    custom_fields("https://xenserver", "root", password, "web-01")
"""

from connection import connect
from helpers import vm_by_name


def custom_fields(url, username, password, vm_name):
    """XenCenter's custom fields are stored in other_config under "XenCenter.CustomFields.<name>"."""
    session = connect(url, username, password)
    vm = vm_by_name(session, vm_name)
    key = "XenCenter.CustomFields.Owner"
    session.xenapi.VM.add_to_other_config(vm, key, "Platform Team")
    print("Custom field Owner = %s" % session.xenapi.VM.get_other_config(vm)[key])

    session.xenapi.VM.remove_from_other_config(vm, key)
    print("OK: custom-fields")
    session.xenapi.session.logout()
