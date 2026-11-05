"""Configure console access.

Tighten how consoles and management traffic may be used: idle timeouts for the pool's own consoles
and for VM consoles, one session at a time, and refusing plain HTTP. Restore every value it changed
afterwards.

Run it::

    configure_console_access("https://xenserver", "root", password)
"""

from connection import connect


def configure_console_access(url, username, password):
    """Tighten how consoles and management traffic may be used, then put back whatever was there
    before.

    Idle console sessions are set at two levels -- the pool's own management consoles and the
    VM consoles it serves -- and a host can override the pool's. Requiring HTTPS refuses plain
    HTTP to the management interface altogether."""
    session = connect(url, username, password)
    x = session.xenapi
    pool = x.pool.get_all()[0]
    host = x.pool.get_master(pool)

    # NB: pool.https_only and pool.console_idle_timeout are SET below but never read back AT THE POOL
    # LEVEL. SDK 26.14 generates a setter and no getter for either there, because both are really
    # fan-outs that call the equivalent Host.set_* on every host rather than pool fields of their own.
    # host.https_only and host.console_idle_timeout ARE ordinary readable fields, so read this host's
    # values back through them instead, to show the effect and to know what to restore.
    before_vm_console_idle_timeout = x.pool.get_vm_console_idle_timeout(pool)
    before_limit_console_sessions = x.pool.get_limit_console_sessions(pool)
    before_host_console_idle_timeout = x.host.get_console_idle_timeout(host)
    before_host_https_only = x.host.get_https_only(host)
    print("  %-26s %ss" % ("VM console idle timeout", before_vm_console_idle_timeout))
    print("  %-26s %s" % ("limit console sessions", before_limit_console_sessions))
    print("  %-26s %ss" % ("host console idle timeout", before_host_console_idle_timeout))
    print("  %-26s %s" % ("host https only", before_host_https_only))

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
    print("  %-26s %s" % ("host https only", x.host.get_https_only(host)))

    x.pool.set_https_only(pool, before_host_https_only)
    x.pool.set_console_idle_timeout(pool, str(before_host_console_idle_timeout))
    x.pool.set_vm_console_idle_timeout(pool, str(before_vm_console_idle_timeout))
    x.pool.set_limit_console_sessions(pool, before_limit_console_sessions)
    x.host.set_console_idle_timeout(host, str(before_host_console_idle_timeout))
    print("  restored")
    print("OK: configure-console-access")
    session.logout()
