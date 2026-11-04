# Send logs to a remote syslog server.
#
# Point a host's logs at a remote syslog server — and reconfigure the daemon, without which the setting is
# recorded but nothing changes.
#
# Run it:
#   ./workflows.sh configure-syslog https://xenserver root "$password"

configure_syslog() {
    pool=$(first_csv "$(xe pool-list --minimal)")
    host_uuid=$(xe pool-param-get uuid=$pool param-name=master)
    syslog_server=192.0.2.50

    logging=$(xe host-param-get uuid=$host_uuid param-name=logging)
    echo "$(xe host-param-get uuid=$host_uuid param-name=name-label) logging: ${logging:-(local only)}"

    # Two steps, and the second is the one that is easy to miss: setting the destination only
    # records it, and the host keeps logging locally until the syslog daemon is reconfigured to
    # pick the setting up. (Removing a key that is not there is an error, hence the || true.)
    xe host-param-remove uuid=$host_uuid param-name=logging param-key=syslog_destination >/dev/null 2>&1 || true
    xe host-param-set uuid=$host_uuid logging:syslog_destination=$syslog_server
    xe host-syslog-reconfigure host-uuid=$host_uuid
    echo "  now logging to: $(xe host-param-get uuid=$host_uuid param-name=logging param-key=syslog_destination)"

    xe host-param-remove uuid=$host_uuid param-name=logging param-key=syslog_destination
    xe host-syslog-reconfigure host-uuid=$host_uuid
    logging=$(xe host-param-get uuid=$host_uuid param-name=logging)
    echo "  restored: ${logging:-(local only)}"
    echo "OK: configure-syslog"
}
