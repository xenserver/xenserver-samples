"""Configure SNMP monitoring.

Configure a host's SNMP agent through the monitoring plugin: read its configuration, enable it with
a community string, then read the configuration and running status back.
"""

import json
import uuid

from connection import connect


def configure_snmp(url, username, password, trap_destination="192.0.2.50"):
    """Enable the SNMP agent on every host with a community string and a trap destination, through
    the snmp plugin.

    nmss is the list of real trap destinations SNMP notifications go to - an empty list never
    configures where traps actually go, which is the whole point of "configure SNMP monitoring".
    Plugin calls are per-host, so configure every host, and restore each one to disabled again
    afterwards."""
    session = connect(url, username, password)
    config = {
        "common": {"enabled": "yes", "debug_log": "no"},
        "agent": {"v2c": "yes", "v3": "no", "community": "sdk-community", "user_name": "",
                  "authentication_password": "", "authentication_protocol": "",
                  "privacy_password": "", "privacy_protocol": ""},
        # Each trap destination needs a uuid of its own: the plugin refuses the whole config without one.
        "nmss": [{"uuid": str(uuid.uuid4()), "address": trap_destination, "port": 162, "v2c": "yes", "v3": "no",
                  "community": "sdk-community", "user_name": "", "authentication_password": "",
                  "authentication_protocol": "", "privacy_password": "", "privacy_protocol": ""}],
    }
    for host in session.xenapi.host.get_all():
        def snmp(fn, args=None, host=host):
            return json.loads(session.xenapi.host.call_plugin(host, "snmp", fn, args or {}))
        # The plugin reports a refused config in its answer, not as an API error: check it.
        answer = snmp("set-config", {"config": json.dumps(config)})
        if answer["code"] != 0:
            raise RuntimeError("set-config refused the configuration: %s" % answer["message"])
        status = snmp("status")["result"]
        cfg = snmp("get-config")["result"]
        label = session.xenapi.host.get_name_label(host)
        print("%s: SNMP enabled: %s / %s" % (label, status["enabled"], status["active"]))
        print("  community: %s, trap destination: %s"
              % (cfg["agent"]["community"], cfg["nmss"][0]["address"] if cfg["nmss"] else "(none)"))
        snmp("set-config", {"config": json.dumps({"common": {"enabled": "no"}})})  # restore
    print("OK: configure-snmp")
    session.logout()
