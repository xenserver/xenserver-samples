# Configure NRPE monitoring.
#
# Configure a host's NRPE (Nagios Remote Plugin Executor) agent through the monitoring plugin: read its status
# and configuration, enable it and permit a monitoring host, then read it back.
#
# Run it:
#   ./workflows.sh configure-nrpe https://xenserver root "$password"

# host-call-plugin is per-host - there is no pool-wide fan-out for plugin calls, unlike pool-enable-ssh -
# so configure every host, and disable NRPE again afterwards (the original left it enabled with no
# tidy-up at all).
configure_nrpe() {
    for h in $(each_csv "$(xe host-list --minimal)"); do
        echo "$(xe host-param-get uuid=$h param-name=name-label): NRPE status before: $(xe host-call-plugin host-uuid=$h plugin=nrpe fn=status)"
        xe host-call-plugin host-uuid=$h plugin=nrpe fn=enable >/dev/null
        xe host-call-plugin host-uuid=$h plugin=nrpe fn=set-config \
            args:allowed_hosts=127.0.0.1,::1,192.0.2.60 args:debug=0 args:ssl_logging=0x00 >/dev/null
        xe host-call-plugin host-uuid=$h plugin=nrpe fn=restart >/dev/null
        echo "  status after:  $(xe host-call-plugin host-uuid=$h plugin=nrpe fn=status)"
        xe host-call-plugin host-uuid=$h plugin=nrpe fn=disable >/dev/null   # restore
    done
    echo "OK: configure-nrpe"
}
