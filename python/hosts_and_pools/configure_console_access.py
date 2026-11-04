"""Configure console access.

Tighten how consoles and management traffic may be used: idle timeouts for the pool's own consoles
and for VM consoles, one session at a time, and refusing plain HTTP.

Run it::

    configure_console_access("https://xenserver", "root", password)
"""

from connection import connect


def configure_console_access(url, username, password):
    """Tighten how consoles and management traffic may be used.

    Idle console sessions are set at two levels -- the pool's own management consoles and the
    VM consoles it serves -- and a host can override the pool's. Requiring HTTPS refuses plain
    HTTP to the management interface altogether."""
    session = connect(url, username, password)
    x = session.xenapi
    pool = x.pool.get_all()[0]
    host = x.pool.get_master(pool)

    # NB: pool.https_only and pool.console_idle_timeout are SET below but never read back. SDK 26.14
    # generates a setter and no getter for both (unlike host.console_idle_timeout, which has both), so
    # they cannot be read through the typed bindings at all — and a sample that reached past its own
    # binding to show a value would be teaching a workaround rather than the API.
    print("  %-26s %ss" % ("VM console idle timeout", x.pool.get_vm_console_idle_timeout(pool)))
    print("  %-26s %s" % ("limit console sessions", x.pool.get_limit_console_sessions(pool)))
    print("  %-26s %ss" % ("host console idle timeout", x.host.get_console_idle_timeout(host)))

    # Ten minutes of inactivity, one console session at a time, and no plain HTTP.
    x.pool.set_console_idle_timeout(pool, "600")
    x.pool.set_vm_console_idle_timeout(pool, "600")
    x.pool.set_limit_console_sessions(pool, True)
    x.host.set_console_idle_timeout(host, "300")
    x.pool.set_https_only(pool, True)

    print("after tightening:")
    print("  %-26s %ss" % ("VM console idle timeout", x.pool.get_vm_console_idle_timeout(pool)))
    print("  %-26s %s" % ("limit console sessions", x.pool.get_limit_console_sessions(pool)))
    print("  %-26s %ss" % ("host console idle timeout", x.host.get_console_idle_timeout(host)))

    x.pool.set_https_only(pool, False)
    x.pool.set_console_idle_timeout(pool, "0")
    x.pool.set_vm_console_idle_timeout(pool, "0")
    x.pool.set_limit_console_sessions(pool, False)
    x.host.set_console_idle_timeout(host, "0")
    print("  restored")
    print("OK: configure-console-access")
    session.logout()
