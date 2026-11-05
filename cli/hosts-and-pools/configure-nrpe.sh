# Configure NRPE monitoring.
#
# Configure a host's NRPE (Nagios Remote Plugin Executor) agent through the monitoring plugin: read its status
# and configuration, enable it and permit a monitoring host, then read it back.
#
# Run it:
#   ./workflows.sh configure-nrpe https://xenserver root "$password"

# host-call-plugin is per-host - there is no pool-wide fan-out for plugin calls, unlike pool-enable-ssh -
# so configure every host, and restore each one to exactly the state (enabled or not, and its
# configuration) it was found in afterwards.
configure_nrpe() {
    for h in $(each_csv "$(xe host-list --minimal)"); do
        # Capture what we're about to change, to put back afterwards.
        status_before=$(xe host-call-plugin host-uuid=$h plugin=nrpe fn=status)
        was_enabled=false
        [ "${status_before##* }" = "enabled" ] && was_enabled=true
        config_before=$(xe host-call-plugin host-uuid=$h plugin=nrpe fn=get-config)
        allowed_hosts_before=$(echo "$config_before" | sed -n 's/^allowed_hosts: *//p')
        debug_before=$(echo "$config_before" | sed -n 's/^debug: *//p')
        ssl_logging_before=$(echo "$config_before" | sed -n 's/^ssl_logging: *//p')

        echo "$(xe host-param-get uuid=$h param-name=name-label): NRPE status before: $status_before"
        xe host-call-plugin host-uuid=$h plugin=nrpe fn=enable >/dev/null
        xe host-call-plugin host-uuid=$h plugin=nrpe fn=set-config \
            args:allowed_hosts=127.0.0.1,::1,192.0.2.60 args:debug=0 args:ssl_logging=0x00 >/dev/null
        xe host-call-plugin host-uuid=$h plugin=nrpe fn=restart >/dev/null
        echo "  status after:  $(xe host-call-plugin host-uuid=$h plugin=nrpe fn=status)"

        # Restore exactly what was found, rather than always disabling: a host that already had NRPE
        # enabled and configured should not be left changed.
        xe host-call-plugin host-uuid=$h plugin=nrpe fn=set-config \
            "args:allowed_hosts=$allowed_hosts_before" "args:debug=$debug_before" "args:ssl_logging=$ssl_logging_before" >/dev/null
        if $was_enabled; then
            xe host-call-plugin host-uuid=$h plugin=nrpe fn=restart >/dev/null
        else
            xe host-call-plugin host-uuid=$h plugin=nrpe fn=disable >/dev/null
        fi
    done
    echo "OK: configure-nrpe"
}
