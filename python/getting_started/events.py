"""Event monitoring.

Subscribe to the event stream and observe a change land as an event — the mechanism for keeping a
client's view of the pool live.

Run it::

    events("https://xenserver", "root", password, "web-01")
"""

from connection import connect
from helpers import vm_by_name


def events(url, username, password, vm_name):
    """Watch the event stream and observe a change we make to the named VM land as an event."""
    session = connect(url, username, password)
    event_from = getattr(session.xenapi.event, "from")  # 'from' is a Python keyword

    # An empty token yields the current world and a fresh token to watch from.
    batch = event_from(["VM"], "", 1.0)
    token = batch["token"]
    print("Established event token after initial snapshot.")

    # Make a change, then poll for it.
    vm_ref = vm_by_name(session, vm_name)
    original = session.xenapi.VM.get_name_description(vm_ref)
    session.xenapi.VM.set_name_description(vm_ref, "changed-to-trigger-event")

    batch = event_from(["VM"], token, 5.0)
    print("Received %d event(s) after the change." % len(batch["events"]))
    for ev in batch["events"][:3]:
        print("  - %s %s" % (ev["operation"], ev["class"]))

    session.xenapi.VM.set_name_description(vm_ref, original)  # put it back
    print("OK: events")
    session.xenapi.session.logout()
