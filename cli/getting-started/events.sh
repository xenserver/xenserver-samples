# Event monitoring.
#
# Subscribe to the event stream and observe a change land as an event — the mechanism for keeping a client's
# view of the pool live.
#
# Run it:
#   ./workflows.sh events https://xenserver root "$password"

events() {
    vm=$(vm_uuid web-01)
    original=$(remote_xe vm-param-get uuid=$vm param-name=name-description)

    # event-wait blocks until the object matches the condition, so there has to be something left to
    # happen when it starts watching: make the change in the background, timed to land only after the
    # foreground event-wait below is already watching for it.
    (sleep 2; remote_xe vm-param-set uuid=$vm name-description="changed-to-trigger-event") &
    remote_xe event-wait class=vm uuid=$vm name-description="changed-to-trigger-event"
    echo "Observed web-01's name-description change via event-wait"

    remote_xe vm-param-set uuid=$vm name-description="$original"  # put it back
    ok events
}
