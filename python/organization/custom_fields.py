"""Custom fields.

Attach and read a custom name/value field on a VM -- arbitrary metadata you define. A management client
only shows a field once it has been DEFINED for the pool; the value on the object is a separate step.
This sample does both.

Run it::

    custom_fields("https://xenserver", "root", password, "web-01")
"""

from xml.etree import ElementTree

from connection import connect
from helpers import vm_by_name

CUSTOM_FIELD_BASE_KEY = "XenCenter.CustomFields"
FIELD_NAME = "Owner"
FIELD_KEY = "%s.%s" % (CUSTOM_FIELD_BASE_KEY, FIELD_NAME)


def custom_fields(url, username, password, vm_name):
    """Define the Owner custom field if it is not defined yet, assign it a value, read it back, then
    tidy up: drop the value always, and the definition only if this sample added it."""
    session = connect(url, username, password)
    vm = vm_by_name(session, vm_name)
    pool = session.xenapi.pool.get_all()[0]

    # The pool's custom field DEFINITIONS (name and type, String or Date) live in a small XML document
    # in pool.gui_config["XenCenter.CustomFields"] (the key keeps its historical name); a client shows
    # no field without one, no matter what value an object carries under XenCenter.CustomFields.<name>.
    previous_xml = session.xenapi.pool.get_gui_config(pool).get(CUSTOM_FIELD_BASE_KEY)
    root = (ElementTree.fromstring(previous_xml) if previous_xml
            else ElementTree.Element("CustomFieldDefinitions"))
    added_definition = all(child.get("name") != FIELD_NAME for child in root)
    if added_definition:
        ElementTree.SubElement(root, "CustomFieldDefinition", {"name": FIELD_NAME, "type": "String"})
        session.xenapi.pool.add_to_gui_config(
            pool, CUSTOM_FIELD_BASE_KEY, ElementTree.tostring(root, encoding="unicode"))
    print("Field defined: %s" % added_definition)

    # With the field defined, giving it a value on an object is a plain other_config write.
    session.xenapi.VM.add_to_other_config(vm, FIELD_KEY, "Platform Team")
    print("Custom field Owner = %s" % session.xenapi.VM.get_other_config(vm)[FIELD_KEY])

    session.xenapi.VM.remove_from_other_config(vm, FIELD_KEY)
    if added_definition:
        # Only this sample's own definition is ours to remove, and only by putting back the pool's
        # previous gui_config value exactly (there may be other definitions alongside it).
        if previous_xml is None:
            session.xenapi.pool.remove_from_gui_config(pool, CUSTOM_FIELD_BASE_KEY)
        else:
            session.xenapi.pool.add_to_gui_config(pool, CUSTOM_FIELD_BASE_KEY, previous_xml)
    print("OK: custom-fields")
    session.xenapi.session.logout()
