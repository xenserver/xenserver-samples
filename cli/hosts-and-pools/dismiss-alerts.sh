# Raise and dismiss alerts.
#
# List the pool's alerts, then dismiss one — what the Notifications view does.
#
# Run it:
#   ./workflows.sh dismiss-alerts https://xenserver root "$password"

dismiss_alerts() {
    echo "Alerts:         $(count_csv "$(xe message-list --minimal)")"
    # Sorted, for a deterministic choice of which one to dismiss (message-list's own order is not).
    msg=$(xe message-list --minimal | tr ',' '\n' | sort | head -n 1)
    if [ -n "$msg" ]; then
        echo "Dismissing:     $(xe message-param-get uuid=$msg param-name=name)"
        xe message-destroy uuid=$msg
        echo "Alerts left:    $(count_csv "$(xe message-list --minimal)")"
    else
        echo "No alerts to dismiss."
    fi
    echo "OK: dismiss-alerts"
}
