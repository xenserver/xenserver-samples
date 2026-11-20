"""Tag and organize objects.

Organize a pool with tags and folders: add tags to a VM and a host (tags work on any object type),
place the VM in a folder, read it all back, then tidy up.

Run it::

    tags_and_folders("https://xenserver", "root", password, "web-01")
"""

from connection import connect
from helpers import vm_by_name


def tags_and_folders(url, username, password, vm_name):
    """Tag a VM and a host, and place the VM in a folder — the data behind Objects-by-Tag/Folder."""
    session = connect(url, username, password)
    vm = vm_by_name(session, vm_name)
    host = session.xenapi.host.get_all()[0]

    # Tags work on any object type (VM, host, SR, network, …).
    session.xenapi.VM.add_tags(vm, "web")
    session.xenapi.host.add_tags(host, "gold")
    print("VM tags:   %s" % session.xenapi.VM.get_tags(vm))
    print("Host tags: %s" % session.xenapi.host.get_tags(host))

    # Folder placement lives in other_config["folder"] as a leading-slash path.
    session.xenapi.VM.add_to_other_config(vm, "folder", "/Production/Web")
    print("VM folder: %s" % session.xenapi.VM.get_other_config(vm).get("folder"))

    # Tidy up.
    session.xenapi.VM.remove_tags(vm, "web")
    session.xenapi.host.remove_tags(host, "gold")
    session.xenapi.VM.remove_from_other_config(vm, "folder")
    print("OK: tags-and-folders")
    session.xenapi.session.logout()
