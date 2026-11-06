"""Restart a host.

Take a host down and bring it back: stop it accepting new VMs, move the ones it is running
elsewhere, reboot it, then power it right off and back on again.
"""

import time

from connection import connect
from helpers import enable_when_booted, host_live


def restart_host(url, username, password):
    """Take a host down and bring it back.

    Rebooting a host is never just the reboot: anything running on it has to go
    somewhere first, and the host has to stop accepting new VMs while that happens.
    Disable, evacuate, reboot, re-enable. Disabling with the default auto_enable=true clears itself
    once the host's toolstack is back up; an explicit enable doesn't depend on that, or on when.
    Powering it right off and back on again is a second, separate demonstration, and only a
    meaningful one if the host actually has an out-of-band power-on mode configured: a real
    host.power_on has no retry of its own and simply fails if none is set up, leaving the host off
    with no API-level way to revive it."""
    session = connect(url, username, password)
    x = session.xenapi
    pool = x.pool.get_all()[0]

    # Not the coordinator: it is the host this session is talking to, and taking it down
    # would drop the connection underneath the rest of the example.
    coordinator = x.pool.get_master(pool)
    host = next(h for h in x.host.get_all() if h != coordinator)
    print("Restarting %s" % x.host.get_name_label(host))
    print("  enabled=%s, guests=%d" % (x.host.get_enabled(host), guest_count(x, host)))

    # Disabled means "accept no new VMs"; it does not move anything on its own.
    x.host.disable(host)
    print("  disabled:   enabled=%s" % x.host.get_enabled(host))

    # Evacuate moves the guests elsewhere in the pool. Afterwards only the control domain
    # -- the host's own management VM, which cannot move -- is left.
    x.host.evacuate(host)
    print("  evacuated:  guests=%d" % guest_count(x, host))

    x.host.reboot(host)
    # A real reboot takes minutes. Wait for the host to drop out and come back (live in its
    # host_metrics), then enable it. A host disabled the default way (auto_enable=true) re-enables
    # itself once its toolstack is up again, but only then - and one disabled with auto_enable=false
    # never does - so enable it explicitly rather than depend on either.
    _wait_for_host_live(x, host, False, timeout=600)
    _wait_for_host_live(x, host, True, timeout=1200, interval=10)
    enable_when_booted(x, host)
    print("  rebooted, re-enabled: enabled=%s" % x.host.get_enabled(host))

    # The other ending: off, and back on out of band -- but only demonstrated if that is actually
    # configured, and waiting for each transition before starting the next.
    if x.host.get_power_on_mode(host):
        x.host.disable(host)
        x.host.shutdown(host)
        _wait_for_host_live(x, host, False)
        print("  shut down:  live=%s" % host_live(x, host))
        x.host.power_on(host)
        _wait_for_host_live(x, host, True, timeout=1200, interval=10)
        print("  powered on: live=%s" % host_live(x, host))
        enable_when_booted(x, host)
        print("  re-enabled: enabled=%s" % x.host.get_enabled(host))
    else:
        print("  skipping shutdown/power-on: no out-of-band power-on mode is configured on this host")

    print("OK: restart-host")
    session.logout()


def _wait_for_host_live(x, host, want, timeout=60, interval=2):
    """Poll host_metrics.live until it matches, rather than issuing the next power command
    immediately - real out-of-band power control has no retry of its own, so a tool that doesn't
    wait can issue a second command while the first is still in flight."""
    deadline = time.time() + timeout
    while host_live(x, host) != want:
        if time.time() > deadline:
            raise RuntimeError("host did not reach live=%s in time" % want)
        time.sleep(interval)


def guest_count(x, host):
    """Resident VMs excluding the control domain, which never moves."""
    return len([v for v in x.host.get_resident_VMs(host)
                if not x.VM.get_is_control_domain(v)])
