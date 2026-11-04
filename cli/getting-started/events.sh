# Event monitoring.
#
# Subscribe to the event stream and observe a change land as an event — the mechanism for keeping a client's
# view of the pool live.
#
# Run it:
#   ./workflows.sh events https://xenserver root "$password"

events() {
    vm=$(vm_uuid web-01)
    # event-wait blocks until the object matches; here the condition already holds, so it returns at once.
    xe event-wait class=vm uuid=$vm power-state=running
    echo "web-01 reached power-state=running"
    echo "OK: events"
}
