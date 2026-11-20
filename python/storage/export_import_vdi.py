"""Copy a disk's contents (raw export and import).

Upload data into a virtual disk, download the disk's raw contents and copy them into a second disk,
then check that the copy matches. Disk contents travel as HTTP transfers alongside the API.

Run it::

    export_import_vdi("https://xenserver", "root", password, "Shared NFS")
"""

import hashlib
import os
import ssl
import time
import urllib.request

from connection import connect
from helpers import sr_by_name

MIB = 1024 * 1024


def export_import_vdi(url, username, password, sr_name):
    """Fill a new disk on sr_name with data, then copy it to a second disk through its raw contents.

    A disk's contents are not XenAPI calls: GET /export_raw_vdi reads them and PUT /import_raw_vdi
    writes them, both alongside the API with the session id in the query string. format=raw is every
    byte of the disk, so a raw export is as large as the disk's virtual size (format=vhd sends only
    the allocated blocks). Name a task in task_id to learn how the transfer ended: an HTTP 200 only
    means the server accepted the request."""
    session = connect(url, username, password)
    x = session.xenapi
    sr = sr_by_name(session, sr_name)
    ctx = ssl._create_unverified_context()

    def new_disk(name, size):
        return x.VDI.create({"name_label": name, "SR": sr, "virtual_size": str(size), "type": "user",
                             "sharable": False, "read_only": False, "other_config": {}})

    def transfer(method, path, vdi, data=None):
        """One raw transfer of vdi's contents, waiting for its task to finish."""
        task = x.task.create("sdk-example-%s" % path, "")
        try:
            request = urllib.request.Request(
                "%s/%s?session_id=%s&task_id=%s&vdi=%s&format=raw" % (url, path, session._session, task, vdi),
                data=data, method=method)
            with urllib.request.urlopen(request, context=ctx) as response:
                body = response.read()
            while x.task.get_status(task) == "pending":
                time.sleep(0.5)
            if x.task.get_status(task) != "success":
                raise RuntimeError("%s failed: %s" % (path, x.task.get_error_info(task)))
        finally:
            x.task.destroy(task)
        return body

    size = 8 * MIB
    original = new_disk("sdk-example-raw-source", size)
    copy = new_disk("sdk-example-raw-copy", size)
    try:
        data = os.urandom(size)
        transfer("PUT", "import_raw_vdi", original, data)
        print("Uploaded %d MiB into %s" % (size // MIB, x.VDI.get_name_label(original)))

        exported = transfer("GET", "export_raw_vdi", original)
        print("Downloaded %d MiB of raw contents" % (len(exported) // MIB))

        transfer("PUT", "import_raw_vdi", copy, exported)
        print("Copied them into %s" % x.VDI.get_name_label(copy))

        same = hashlib.sha256(transfer("GET", "export_raw_vdi", copy)).digest() == hashlib.sha256(data).digest()
        print("The copy %s the original" % ("matches" if same else "DIFFERS FROM"))
        if not same:
            raise RuntimeError("the copied disk does not match the data uploaded")
    finally:
        for vdi in (original, copy):
            x.VDI.destroy(vdi)
    print("OK: export-import-vdi")
    session.logout()
