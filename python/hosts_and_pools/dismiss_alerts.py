"""Raise and dismiss alerts.

List the pool's alerts, then dismiss one — what the Notifications view does.
"""

from connection import connect


def dismiss_alerts(url, username, password):
    """List the pool's alerts and dismiss one, as the Notifications view does."""
    session = connect(url, username, password)
    messages = session.xenapi.message.get_all_records()
    print("Alerts:         %d" % len(messages))

    if not messages:
        print("No alerts to dismiss.")
    else:
        ref = sorted(messages.keys())[0]
        print("Dismissing:     %s (priority %s)" % (messages[ref]["name"], messages[ref]["priority"]))
        session.xenapi.message.destroy(ref)
        print("Alerts left:    %d" % len(session.xenapi.message.get_all_records()))
    print("OK: dismiss-alerts")
    session.xenapi.session.logout()
