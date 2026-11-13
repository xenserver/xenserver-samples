"""Rename an object.

Change an object's name and read it back — how any object is renamed.

Run it::

    rename_object("https://xenserver", "root", password, "web-01")
"""

from connection import connect
from helpers import vm_by_name


def rename_object(url, username, password, vm_name):
    """Rename the named VM, then restore its original name so the example is repeatable."""
    session = connect(url, username, password)
    vm = vm_by_name(session, vm_name)
    original = session.xenapi.VM.get_name_label(vm)
    session.xenapi.VM.set_name_label(vm, "sdk-renamed")
    print("Renamed '%s' -> '%s'" % (original, session.xenapi.VM.get_name_label(vm)))
    session.xenapi.VM.set_name_label(vm, original)  # restore so the example is repeatable
    print("OK: rename-object")
    session.xenapi.session.logout()
