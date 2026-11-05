# Handle an API error.
#
# Catch an API failure and inspect its error code and parameters — the shape of every error the API returns,
# and how to react to it robustly.
#
# Run it:
#   ./workflows.sh error-handling https://xenserver root "$password"

error_handling() {
    # xe prints a failed call's error (its code and parameters, or a friendly rendering of a common
    # one) to stderr; capture it instead of letting it go straight to the terminal.
    if out=$(xe vm-param-get uuid=this-uuid-does-not-exist param-name=uuid 2>&1); then
        echo "unexpected: no error"
    else
        echo "Caught expected failure:"
        echo "$out"
    fi
    echo "OK: error-handling"
}
