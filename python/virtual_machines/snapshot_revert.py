"""Snapshot & revert.

Take a snapshot of a VM and then revert the VM back to that point-in-time, as you would before a
risky change.

Run it::

    snapshot_revert("https://xenserver", "root", password, "web-01")
"""

import ssl
import urllib.error
import urllib.request

from connection import connect
from helpers import destroy_vm_and_disks, vm_by_name


def snapshot_revert(url, username, password, vm_name, snapshot_name="sdk-example-snapshot"):
    """Snapshot the named VM, then revert the VM back to that snapshot.

    Reverting to a plain snapshot always leaves the VM Halted (xapi hard-shuts-down a running VM
    before reverting it), even if it was Running a moment ago - restart it afterwards if that's
    how we found it, so the workflow actually restores what it changed."""
    session = connect(url, username, password)
    vm_ref = vm_by_name(session, vm_name)
    print("Snapshotting VM: %s" % session.xenapi.VM.get_name_label(vm_ref))
    was_running = session.xenapi.VM.get_power_state(vm_ref) == "Running"

    snap_ref = session.xenapi.VM.snapshot(vm_ref, snapshot_name)
    print("Created snapshot: %s" % session.xenapi.VM.get_uuid(snap_ref))

    # A client shows a thumbnail of what was on screen when the snapshot was taken, captured from the
    # VM's console at that moment. It is an HTTP transfer alongside the API, not an API call, so the
    # session id travels in the query string. ref names the VM's VNC (rfb) console, as XenCenter does
    # (the VM itself works too). Only a running VM has a console to capture, and a host that can't
    # reach it answers 404 or 500 instead of an image: the picture is incidental, so carry on.
    if session.xenapi.VM.get_power_state(vm_ref) == "Running":
        console = next(c for c in session.xenapi.VM.get_consoles(vm_ref)
                       if session.xenapi.console.get_protocol(c) == "rfb")
        try:
            with urllib.request.urlopen(
                    "%s/vncsnapshot?session_id=%s&ref=%s" % (url, session._session, console),
                    context=ssl._create_unverified_context()) as response:
                print("Thumbnail:      %d bytes of PNG" % len(response.read()))
        except urllib.error.HTTPError as e:
            print("Thumbnail:      none (the host answered HTTP %d)" % e.code)
    else:
        print("Thumbnail:      none (the VM is not running, so it has no console)")

    session.xenapi.VM.revert(snap_ref)
    print("Reverted VM to the snapshot.")

    if was_running:
        session.xenapi.VM.start(vm_ref, False, True)
        print("Restarted the VM (it was running before the revert).")

    # A snapshot is itself a (special) VM record, with its own snapshot disks; destroy both to
    # clean up (the source VM's disks are untouched - they are not the snapshot's).
    destroy_vm_and_disks(session, snap_ref)
    print("OK: snapshot-revert")
    session.xenapi.session.logout()
