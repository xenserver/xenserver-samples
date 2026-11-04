# Trace API calls.
#
# Send a W3C trace context with your API calls, so the work the pool does for them is recorded as part of your
# application's distributed trace.
#
# Run it:
#   ./workflows.sh trace-api-calls https://xenserver root "$password"

# Send a W3C trace context with every command, so the work the pool does for them is recorded as part of
# your application's distributed trace. xe sends $TRACEPARENT to the server as a traceparent header (or
# take --traceparent <value>); in a traced script, export the caller's own. The Windows xe.exe that
# ships with XenCenter does not send one.
trace_api_calls() {
    # version 00, a 16-byte trace id, the 8-byte id of the calling span, and flags 01 (sampled)
    local trace_id span_id
    trace_id=$(od -An -N16 -tx1 /dev/urandom); trace_id=${trace_id//[[:space:]]/}
    span_id=$(od -An -N8 -tx1 /dev/urandom); span_id=${span_id//[[:space:]]/}
    local -x TRACEPARENT="00-$trace_id-$span_id-01"
    echo "Trace $trace_id: each command sends traceparent: $TRACEPARENT"
    local hosts
    hosts=$(xe host-list --minimal)
    echo "The pool has $(count_csv "$hosts") hosts"
    echo "OK: trace-api-calls"
}
