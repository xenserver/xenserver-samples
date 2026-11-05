# Connecting to a pool: where xe should send its commands, and the one place the connection details
# live (sourced by workflows.sh, which sets url, user and pass).

# Parse host:port from the URL with pure bash parameter-expansion (no sed): strip the scheme, then any
# trailing path, then split host from port. On Windows every sed/cut/tr/grep is a process launch, so these
# examples parse `xe --minimal` output with bash builtins - each `xe` call is unavoidable, but the string
# plumbing around it stays in-process.
_hp=${url#*://}; _hp=${_hp%%/*}   # host[:port]
host=${_hp%%:*}
# A real host serves the CLI over TLS on 443, which is xe's default, so a URL with no port (or :443) needs
# no -p. xe uses TLS only on 443, so a test endpoint on any other port serves the CLI over plain HTTP on
# the next port up.
xe_opts=()
if [ "$_hp" != "$host" ] && [ "${_hp##*:}" != 443 ]; then xe_opts=(-p $((${_hp##*:} + 1))); fi
# The Windows xe.exe asks before trusting a certificate it has not seen, such as a host's self-signed one,
# and fails when there is no console to answer; accept it, as the SDK examples do. The Linux xe does not
# ask, and does not take these options.
case "${XE_EXE:-xe}" in *.exe | *.EXE) xe_opts+=(-no-warn-new-certificates -no-warn-certificates) ;; esac

# --- connect ---
# The one place the connection details live: every example just calls `xe <command> ...`.
xe() {
    # xe reports a failure on stdout. Captured by $(...), that text would land in the variable and set -e
    # would then stop the script without saying why, so pass a failure's output on to stderr instead.
    local out rc=0
    # `command`: when XE_EXE is unset, plain "xe" would be this function calling itself, without end.
    out=$(command "${XE_EXE:-xe}" -s "$host" "${xe_opts[@]}" -u "$user" -pw "$pass" "$@") || rc=$?
    if [ $rc -ne 0 ]; then [ -z "$out" ] || printf '%s\n' "$out" >&2; return $rc; fi
    [ -z "$out" ] || printf '%s\n' "$out"
}

# A pool member refuses every command with HOST_IS_SLAVE, naming the coordinator's address; send
# everything there instead (assuming the coordinator is up).
_probe=$(xe pool-list --minimal 2>&1) || true
if [[ $_probe =~ (Master|Coordinator)\ IP\ address:\ ([0-9A-Fa-f.:]+) ]]; then host=${BASH_REMATCH[2]}; fi
