"""Configure NRPE monitoring.

Configure a host's NRPE (Nagios Remote Plugin Executor) agent through the monitoring plugin: read
its status and configuration, enable it and permit a monitoring host, then read it back.
"""

from connection import connect


def configure_nrpe(url, username, password):
    """Enable the NRPE agent on every host and allow a monitoring host, through the nrpe plugin.

    host.call_plugin is per-host - there is no pool-wide fan-out for plugin calls the way there is
    for pool.enable_ssh - so configure every host in the pool, and restore each one to disabled
    again afterwards."""
    session = connect(url, username, password)
    for host in session.xenapi.host.get_all():
        def nrpe(fn, args=None, host=host):
            return session.xenapi.host.call_plugin(host, "nrpe", fn, args or {})
        label = session.xenapi.host.get_name_label(host)
        print("%s: NRPE status before: %s" % (label, nrpe("status").strip()))
        nrpe("enable")
        nrpe("set-config", {"allowed_hosts": "127.0.0.1,::1,192.0.2.60", "debug": "0", "ssl_logging": "0x00"})
        nrpe("restart")
        print("  status after:  %s" % nrpe("status").strip())
        for line in nrpe("get-config").split("\n"):
            if line.startswith("allowed_hosts:"):
                print("  allowed hosts: %s" % line.split(":", 1)[1].strip())
        nrpe("disable")  # restore: leave it as we found it
    print("OK: configure-nrpe")
    session.logout()
