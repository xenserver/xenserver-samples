# Configure host power on.
#
# Set a host's out-of-band power-on mode and credentials, then read them back.
#
# Run it:
#   ./workflows.sh host-power-on https://xenserver root "$password"

host_power_on() {
    h=$(first_host)
    local original_mode original_config config kv restored
    original_mode=$(remote_xe host-param-get uuid=$h param-name=power-on-mode)
    # A map field prints as "key: value; key2: value2" (empty if there is none) - keep the raw form so
    # it can be split into key=value pairs again below, to restore it rather than just clearing it.
    original_config=$(remote_xe host-param-get uuid=$h param-name=power-on-config)

    # Mode and config travel together: the config carries the credentials the mode needs.
    # "wake-on-lan" is a real, still-supported mode and needs no credentials; the legacy "iLO"/"DRAC"
    # modes were removed from the real power-on plugin and fail the moment host-power-on is actually
    # called ("<mode> script has been removed").
    remote_xe host-set-power-on-mode uuid=$h power-on-mode=wake-on-lan
    echo "Power-on mode:  $(remote_xe host-param-get uuid=$h param-name=power-on-mode)"
    config=$(set_to_csv "$(remote_xe host-param-get uuid=$h param-name=power-on-config)")
    if [ -n "$config" ]; then
        for kv in $(each_csv "$config"); do echo "  ${kv/: /=}"; done
    else
        echo "  no credentials needed"
    fi

    # power-on-mode and power-on-config are both read-only fields (no param-set/param-add of their own) -
    # host-set-power-on-mode is the only way to change either, and it takes both together, so restore the
    # original config the same way it was read, as power-on-config:key=value arguments.
    local -a restore=(uuid=$h power-on-mode="$original_mode")
    config=$(set_to_csv "$original_config")
    if [ -n "$config" ]; then
        for kv in $(each_csv "$config"); do restore+=("power-on-config:${kv/: /=}"); done
    fi
    remote_xe host-set-power-on-mode "${restore[@]}"
    restored=$(remote_xe host-param-get uuid=$h param-name=power-on-mode)
    echo "Restored power-on mode: ${restored:-(none)}"
    ok host-power-on
}
