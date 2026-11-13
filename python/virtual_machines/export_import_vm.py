"""Export and import a VM.

Export a VM to an XVA file and import it back as a new one. These are HTTP transfers alongside the
API rather than API calls, so the session id travels in the query string.

Run it::

    export_import_vm("https://xenserver", "root", password, "db-01")
"""

import os
import re
import ssl
import tarfile
import tempfile
import time
import urllib.request

from connection import connect
from helpers import destroy_vm_and_disks, vm_by_name


def export_import_vm(url, username, password, vm_name):
    """Export a halted VM (vm_name) to an XVA file and import it back as a new VM.

    Export and import are not XenAPI calls: they are HTTP transfers alongside the API, and
    the session id goes in the query string. Everything else about them is ordinary HTTP -
    GET /export writes the archive, PUT /import reads one back.

    One quirk worth knowing if you write your own uploader: the server answers 200 BEFORE
    reading the body, because xapi's own clients wait for the response line before they
    start streaming. Ordinary HTTP libraries send the body first and cope with the early
    reply, so this only matters if you are working at the socket level.

    The new VM's ref is NOT in the /import response body on a real host - the only place it
    appears is the task named in the task_id query parameter, so create one, pass it, and read
    task.get_result() once the upload finishes, the same pattern backup-host-config/wait-for-task
    already use."""
    session = connect(url, username, password)
    x = session.xenapi
    session_id = session._session

    # Name the VM: an export carries every block of its disks, so which VM matters (a large one
    # takes a long time, and fills the disk). Only a halted VM can be exported: its disks must not
    # be changing underneath the copy.
    vm = vm_by_name(session, vm_name)
    if x.VM.get_power_state(vm) != "Halted":
        raise RuntimeError("%s must be halted to be exported" % vm_name)
    name = vm_name
    print("Exporting %s" % name)

    # A unique file, not a fixed name: an export is a real file on disk and two of them running at once
    # would otherwise fight over it.
    handle, path = tempfile.mkstemp(prefix="sdk-example-export-", suffix=".xva")
    os.close(handle)
    ctx = ssl._create_unverified_context()
    with urllib.request.urlopen(
            "%s/export?session_id=%s&uuid=%s" % (url, session_id, x.VM.get_uuid(vm)),
            context=ctx) as response, open(path, "wb") as out:
        exported = 0
        while True:
            chunk = response.read(1024 * 1024)
            if not chunk:
                break
            out.write(chunk)
            exported += len(chunk)
    print("  wrote %.1f MiB to %s" % (exported / (1024.0 ** 2), os.path.basename(path)))

    # An XVA is a tar: ova.xml describes the VM, and the disk blocks follow it in 1 MiB
    # pieces, each with its own checksum.
    with tarfile.open(path) as archive:
        names = archive.getnames()
    print("  archive holds %s and %d disk block(s)"
          % (names[0], len([n for n in names if not n.endswith(".checksum")]) - 1))

    task = x.task.create("vm_import", "importing %s back" % name)
    try:
        # Stream the file rather than reading it into memory: a real VM's export is gigabytes.
        with open(path, "rb") as f:
            request = urllib.request.Request(
                "%s/import?session_id=%s&task_id=%s" % (url, session_id, task),
                data=f, method="PUT", headers={"Content-Length": str(os.path.getsize(path))})
            urllib.request.urlopen(request, context=ctx).read()

        while x.task.get_status(task) == "pending":
            time.sleep(0.5)
        if x.task.get_status(task) != "success":
            raise RuntimeError("import failed: %s" % x.task.get_error_info(task))
        # The result lists the imported VMs (<value><array><data>OpaqueRef:...</data></array></value>
        # on a real host), so take the first reference in it.
        imported = re.search(r"OpaqueRef:[^<]+", x.task.get_result(task)).group(0)
    finally:
        x.task.destroy(task)
    print("  imported as %s" % x.VM.get_name_label(imported))

    # The import brought its own disks along; destroy those too, not just the VM record.
    destroy_vm_and_disks(session, imported)
    os.remove(path)
    print("OK: export-import-vm")
    session.logout()
