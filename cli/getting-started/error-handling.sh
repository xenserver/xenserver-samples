# Handle an API error.
#
# Catch an API failure and inspect its error code and parameters — the shape of every error the API returns,
# and how to react to it robustly.
#
# Run it:
#   ./workflows.sh error-handling https://xenserver root "$password"

error_handling() {
    if xe vm-param-get uuid=this-uuid-does-not-exist param-name=uuid 2>/dev/null; then
        echo "unexpected: no error"
    else
        echo "Caught expected failure: invalid uuid (exit code $?)"
    fi
    echo "OK: error-handling"
}
