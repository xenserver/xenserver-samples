"""Configure host power on.

Set a host's out-of-band power-on mode and credentials, then read them back.
"""

from connection import connect


def host_power_on(url, username, password):
    """Set a host's out-of-band power-on mode and credentials, then read them back."""
    session = connect(url, username, password)
    host_ref = session.xenapi.host.get_all()[0]

    # Save the original mode and config so the example restores the host to how it found it, not to
    # a blank "no power-on configured" state.
    original_mode = session.xenapi.host.get_power_on_mode(host_ref)
    original_config = session.xenapi.host.get_power_on_config(host_ref)

    # Mode and config travel together: the config carries the credentials the mode needs.
    # "wake-on-lan" is a real, still-supported mode and needs no credentials; the legacy "iLO"/
    # "DRAC" modes were removed from the real power-on plugin and fail the moment host.power_on
    # is actually called.
    session.xenapi.host.set_power_on_mode(host_ref, "wake-on-lan", {})
    print("Power-on mode:  %s" % session.xenapi.host.get_power_on_mode(host_ref))
    config = session.xenapi.host.get_power_on_config(host_ref)
    if config:
        for k, v in sorted(config.items()):
            print("  %s = %s" % (k, v))
    else:
        print("  no credentials needed")

    session.xenapi.host.set_power_on_mode(host_ref, original_mode, original_config)
    print("Restored power-on mode: %s" % (session.xenapi.host.get_power_on_mode(host_ref) or "(none)"))
    print("OK: host-power-on")
    session.xenapi.session.logout()
