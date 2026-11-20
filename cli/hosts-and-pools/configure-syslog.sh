# Send logs to a remote syslog server.
#
# Point a host's logs at a remote syslog server — and reconfigure the daemon, without which the setting is
# recorded but nothing changes.
#
# Run it:
#   ./workflows.sh configure-syslog https://xenserver root "$password"

configure_syslog() {
    pool=$(first_csv "$(remote_xe pool-list --minimal)")
    host_uuid=$(remote_xe pool-param-get uuid=$pool param-name=master)
    syslog_server=192.0.2.50

    logging=$(remote_xe host-param-get uuid=$host_uuid param-name=logging)
    echo "$(remote_xe host-param-get uuid=$host_uuid param-name=name-label) logging: ${logging:-(local only)}"
    # Capture the host's previous destination (if any), to put it back afterwards instead of dropping it.
    previous=$(remote_xe_try host-param-get uuid=$host_uuid param-name=logging param-key=syslog_destination 2>/dev/null) || previous=""

    # Two steps, and the second is the one that is easy to miss: setting the destination only
    # records it, and the host keeps logging locally until the syslog daemon is reconfigured to
    # pick the setting up. (Removing a key that is not there is an error, hence the || true.)
    remote_xe_try host-param-remove uuid=$host_uuid param-name=logging param-key=syslog_destination >/dev/null 2>&1 || true
    remote_xe host-param-set uuid=$host_uuid logging:syslog_destination=$syslog_server
    remote_xe host-syslog-reconfigure host-uuid=$host_uuid
    echo "  now logging to: $(remote_xe host-param-get uuid=$host_uuid param-name=logging param-key=syslog_destination)"

    # Put back whatever destination (if any) the host had before, rather than dropping it.
    remote_xe host-param-remove uuid=$host_uuid param-name=logging param-key=syslog_destination
    [ -z "$previous" ] || remote_xe host-param-set uuid=$host_uuid logging:syslog_destination=$previous
    remote_xe host-syslog-reconfigure host-uuid=$host_uuid
    logging=$(remote_xe host-param-get uuid=$host_uuid param-name=logging)
    echo "  restored: ${logging:-(local only)}"
    ok configure-syslog
}
