# Configure SNMP monitoring.
#
# Configure a host's SNMP agent through the monitoring plugin: read its configuration, enable it with a
# community string and trap destination, read the configuration and running status back, then put the
# host's original configuration back.
#
# Run it:
#   ./workflows.sh configure-snmp https://xenserver root "$password"
#
# Optional key=value arguments (default):
#   trap_destination (192.0.2.50)

# The string value of a JSON key, e.g. json_value '{"agent":{"community":"x"}}' community => x. The plugin's
# JSON may come on one line or pretty-printed over several, but every value read here is quoted, so
# parameter expansion alone (no sed/grep process) finds it either way.
json_value() {
    local json=$1 key=$2 rest
    rest=${json#*\"$key\"}
    rest=${rest#*:}
    rest=${rest#*\"}
    echo "${rest%%\"*}"
}

# The JSON *object* value of a key (e.g. "result", the config a get-config answer wraps), brace-matched so
# the object's own nested braces don't confuse the search - unlike json_value, which only reads a quoted
# string. Only {}-depth is tracked, not []: a "nmss":[{...}] array's objects still balance the count
# correctly, since the brackets around them never change it. While inside a quoted string, braces don't
# count at all (in_str), and a backslash-escaped quote doesn't end the string early either.
json_object() {
    local json=$1 key=$2 rest depth=0 i c prev="" in_str="" obj=""
    rest=${json#*\"$key\"}
    rest=${rest#*:}
    rest="${rest#"${rest%%[![:space:]]*}"}"
    [ "${rest:0:1}" = "{" ] || return 1
    for ((i = 0; i < ${#rest}; i++)); do
        c=${rest:i:1}
        obj+="$c"
        if [ -n "$in_str" ]; then
            [ "$c" = '"' ] && [ "$prev" != '\' ] && in_str=""
            prev=$c
            continue
        fi
        case "$c" in
            '"') in_str=1 ;;
            '{') depth=$((depth + 1)) ;;
            '}') depth=$((depth - 1)); [ "$depth" -eq 0 ] && break ;;
        esac
        prev=$c
    done
    echo "$obj"
}

# trap_destination: nmss is the list of real trap destinations SNMP notifications go to - an empty list
# never configures where traps actually go, which is arguably the main point of "configure SNMP
# monitoring". Plugin calls are per-host, so configure every host, and restore each one to its own
# original configuration afterwards.
configure_snmp() {
    local trap_destination config nms_uuid answer status cfg dest before
    trap_destination=$(param trap_destination "192.0.2.50")
    # Each trap destination needs a uuid of its own: the plugin refuses the whole config without one.
    nms_uuid=$(printf '%04x%04x-%04x-4%03x-%04x-%04x%04x%04x' $RANDOM $RANDOM $RANDOM $((RANDOM & 0xfff)) \
        $(( (RANDOM & 0x3fff) | 0x8000 )) $RANDOM $RANDOM $RANDOM)
    config='{"common":{"enabled":"yes","debug_log":"no"},"agent":{"v2c":"yes","v3":"no","community":"sdk-community","user_name":"","authentication_password":"","authentication_protocol":"","privacy_password":"","privacy_protocol":""},"nmss":[{"uuid":"'"$nms_uuid"'","address":"'"$trap_destination"'","port":162,"v2c":"yes","v3":"no","community":"sdk-community","user_name":"","authentication_password":"","authentication_protocol":"","privacy_password":"","privacy_protocol":""}]}'
    for h in $(each_csv "$(remote_xe host-list --minimal)"); do
        # Read the configuration first, to put it back afterwards instead of just disabling.
        before=$(json_object "$(remote_xe host-call-plugin host-uuid=$h plugin=snmp fn=get-config)" result)
        # A real host pretty-prints it over several lines, but xe passes an argument only up to its first
        # line break: put it back on one line (JSON strings never hold a raw line break, so this is safe).
        before=${before//$'\n'/}
        before=${before//$'\r'/}

        # The plugin reports a refused config in its answer, not as an xe error: check it.
        answer=$(remote_xe host-call-plugin host-uuid=$h plugin=snmp fn=set-config "args:config=$config")
        case "$answer" in *'"code": 0'*|*'"code":0'*) ;; *) echo "set-config refused the configuration: $answer" >&2; exit 1 ;; esac
        status=$(remote_xe host-call-plugin host-uuid=$h plugin=snmp fn=status)
        cfg=$(remote_xe host-call-plugin host-uuid=$h plugin=snmp fn=get-config)
        dest=$(json_value "$cfg" address); dest=${dest:-"(none)"}
        echo "$(remote_xe host-param-get uuid=$h param-name=name-label): SNMP enabled: $(json_value "$status" enabled) / $(json_value "$status" active)"
        echo "  community: $(json_value "$cfg" community), trap destination: $dest"
        # Restore: put the host's own configuration back rather than always disabling it.
        answer=$(remote_xe host-call-plugin host-uuid=$h plugin=snmp fn=set-config "args:config=$before")
        case "$answer" in *'"code": 0'*|*'"code":0'*) ;; *) echo "set-config refused restoring the configuration: $answer" >&2; exit 1 ;; esac
    done
    ok configure-snmp
}
