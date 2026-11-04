# Configure SNMP monitoring.
#
# Configure a host's SNMP agent through the monitoring plugin: read its configuration, enable it with a
# community string, then read the configuration and running status back.
#
# Run it:
#   ./workflows.sh configure-snmp https://xenserver root "$password"
#
# Optional key=value arguments (default):
#   trap_destination (192.0.2.50)

# trap_destination: nmss is the list of real trap destinations SNMP notifications go to - an empty list
# never configures where traps actually go, which is arguably the main point of "configure SNMP
# monitoring". Plugin calls are per-host, so configure every host, and restore each one to disabled again
# afterwards.
configure_snmp() {
    local trap_destination config nms_uuid answer
    trap_destination=$(param trap_destination "192.0.2.50")
    # Each trap destination needs a uuid of its own: the plugin refuses the whole config without one.
    nms_uuid=$(printf '%04x%04x-%04x-4%03x-%04x-%04x%04x%04x' $RANDOM $RANDOM $RANDOM $((RANDOM & 0xfff)) \
        $(( (RANDOM & 0x3fff) | 0x8000 )) $RANDOM $RANDOM $RANDOM)
    config='{"common":{"enabled":"yes","debug_log":"no"},"agent":{"v2c":"yes","v3":"no","community":"sdk-community","user_name":"","authentication_password":"","authentication_protocol":"","privacy_password":"","privacy_protocol":""},"nmss":[{"uuid":"'"$nms_uuid"'","address":"'"$trap_destination"'","port":162,"v2c":"yes","v3":"no","community":"sdk-community","user_name":"","authentication_password":"","authentication_protocol":"","privacy_password":"","privacy_protocol":""}]}'
    for h in $(each_csv "$(xe host-list --minimal)"); do
        # The plugin reports a refused config in its answer, not as an xe error: check it.
        answer=$(xe host-call-plugin host-uuid=$h plugin=snmp fn=set-config "args:config=$config")
        case "$answer" in *'"code": 0'*|*'"code":0'*) ;; *) echo "set-config refused the configuration: $answer" >&2; exit 1 ;; esac
        echo "$(xe host-param-get uuid=$h param-name=name-label): SNMP status: $(xe host-call-plugin host-uuid=$h plugin=snmp fn=status)"
        xe host-call-plugin host-uuid=$h plugin=snmp fn=set-config 'args:config={"common":{"enabled":"no"}}' >/dev/null  # restore
    done
    echo "OK: configure-snmp"
}
