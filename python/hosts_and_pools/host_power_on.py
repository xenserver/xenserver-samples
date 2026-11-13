"""Configure host power on.

Set a host's out-of-band power-on mode and credentials, then read them back.
"""

from connection import connect


def host_power_on(url, username, password):
    """Set a host's out-of-band power-on mode and credentials, then read them back."""
    session = connect(url, username, password)
    host_ref = session.xenapi.host.get_all()[0]

    # Mode and config travel together: the config carries the credentials the mode needs.
    # "wake-on-lan" is a real, still-supported mode and needs no credentials; the legacy "iLO"/
    # "DRAC" modes were removed from the real power-on plugin and fail the moment host.power_on
    # is actually called.
    session.xenapi.host.set_power_on_mode(host_ref, "wake-on-lan", {})
    print("Power-on mode:  %s" % session.xenapi.host.get_power_on_mode(host_ref))
    for k, v in sorted(session.xenapi.host.get_power_on_config(host_ref).items()):
        print("  %s = %s" % (k, v))

    session.xenapi.host.set_power_on_mode(host_ref, "", {})
    print("OK: host-power-on")
    session.xenapi.session.logout()
