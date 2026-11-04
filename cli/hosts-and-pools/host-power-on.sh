# Configure host power on.
#
# Set a host's out-of-band power-on mode and credentials, then read them back.
#
# Run it:
#   ./workflows.sh host-power-on https://xenserver root "$password"

host_power_on() {
    h=$(first_host)
    # Mode and config travel together: the config carries the credentials the mode needs.
    # "wake-on-lan" is a real, still-supported mode and needs no credentials; the legacy "iLO"/"DRAC"
    # modes were removed from the real power-on plugin and fail the moment host-power-on is actually
    # called ("<mode> script has been removed").
    xe host-set-power-on-mode uuid=$h power-on-mode=wake-on-lan
    echo "Power-on mode:  $(xe host-param-get uuid=$h param-name=power-on-mode)"

    xe host-set-power-on-mode uuid=$h power-on-mode=
    echo "OK: host-power-on"
}
