# Connecting to a pool: where xe should send its commands, and the one place the connection details
# live (sourced by workflows.sh, which sets url, user and pass). The examples call remote_xe, defined
# below, which runs the xe client against the pool - from any machine, not only a host's own dom0.

# Parse host:port from the URL with pure bash parameter-expansion (no sed): strip the scheme, then any
# trailing path, then split host from port. On Windows every sed/cut/tr/grep is a process launch, so these
# examples parse `xe --minimal` output with bash builtins - each `xe` call is unavoidable, but the string
# plumbing around it stays in-process.
_hp=${url#*://}; _hp=${_hp%%/*}   # host[:port]
host=${_hp%%:*}
# A host serves the CLI over TLS on 443, xe's default port, so a URL with no port (or :443) needs no -p.
# A URL that names another port - a port forward, say - passes it on with -p. The Linux xe still uses TLS
# there; the Windows xe.exe uses TLS only on 443, and plain HTTP on any other port.
xe_opts=()
if [ "$_hp" != "$host" ] && [ "${_hp##*:}" != 443 ]; then xe_opts=(-p "${_hp##*:}"); fi
# The Windows xe.exe asks before trusting a certificate it has not seen, such as a host's self-signed one,
# and fails when there is no console to answer; accept it, as the SDK examples do. The Linux xe does not
# ask, and does not take these options. Accepting a certificate unchecked suits a test pool; in production,
# give the hosts a certificate from a CA you trust.
case "${XE_EXE:-xe}" in *.exe | *.EXE) xe_opts+=(-no-warn-new-certificates -no-warn-certificates) ;; esac

# --- connect ---
# The one place the connection details live: every example calls `remote_xe <command> ...` - the xe client
# with this pool's address and credentials added - rather than xe itself, so none of them repeats them.
#
# This script's temporary files, removed however it ends. (workflows.sh runs the workflow in a subshell,
# so an EXIT trap a workflow sets for its own tidying up doesn't replace this one.)
_tmpfiles=()
trap 'rm -f "${_tmpfiles[@]}"' EXIT
# private_tempfile <variable>: a new temporary file, which mktemp makes readable by its owner only.
private_tempfile() { local f; f=$(mktemp); _tmpfiles+=("$f"); printf -v "$1" '%s' "$f"; }

# The password reaches xe in a file (-pwf), not on its command line, where other users could read it (ps)
# and logging tools could keep it. xe reads the user name from the file's first line and the password from
# its second. The Windows xe.exe has no -pwf, so it gets -u and -pw. The file is written before each call,
# so it always holds the current password (change-root-password changes it mid-run).
# xe_auth <password file> <user> <password>: sets _xe_auth to the options for that user and password.
xe_auth() {
    case "${XE_EXE:-xe}" in
        *.exe | *.EXE) _xe_auth=(-u "$2" -pw "$3") ;;
        *) printf '%s\n%s\n' "$2" "$3" > "$1"; _xe_auth=(-pwf "$1") ;;
    esac
}
private_tempfile _password_file

# xe reports a failure on stdout. Captured by $(...), that text would land in the variable and set -e
# would then stop the script without saying why, so pass a failure's output on to stderr instead, and
# return the real exit status - which workflows.sh's `set -euo pipefail` plus `inherit_errexit` then
# acts on: a plain `xe ...` or a `var=$(xe ...)` assignment stops the whole script. That does not reach
# a failure a `$(...)` only USES - an argument to echo/printf, a `[ ]` test, ... - because the shell
# never looks at that exit status at all; remote_xe_try is this same wrapper under its own name, for a
# call site that is deliberately checking whether xe succeeds (so the distinct name documents the intent,
# even though the function is identical).
remote_xe_try() {
    local out rc=0
    xe_auth "$_password_file" "$user" "$pass"
    out=$("${XE_EXE:-xe}" -s "$host" "${xe_opts[@]}" "${_xe_auth[@]}" "$@") || rc=$?
    if [ $rc -ne 0 ]; then [ -z "$out" ] || printf '%s\n' "$out" >&2; return $rc; fi
    [ -z "$out" ] || printf '%s\n' "$out"
}
# A `$(remote_xe ...)` used inside another command (an argument to echo, a `[ ]` test, ...) is beyond set
# -e's reach: the shell never looks at its exit status. So remote_xe also notes every failed call in a file
# - a variable would not survive the `$(...)` subshell - and ok() (helpers.sh) refuses to report success
# when any call failed, even one set -e could not see.
private_tempfile _xe_failures
remote_xe() { remote_xe_try "$@" || { local rc=$?; echo "xe $1 (exit $rc)" >> "$_xe_failures"; return $rc; }; }

# A pool member refuses every command with HOST_IS_SLAVE, naming the coordinator's address; send
# everything there instead (assuming the coordinator is up). Deliberately remote_xe_try: HOST_IS_SLAVE is
# reported as a failure, and is the expected outcome here as often as not.
_probe=$(remote_xe_try pool-list --minimal 2>&1) || true
if [[ $_probe =~ (Master|Coordinator)\ IP\ address:\ ([0-9A-Fa-f.:]+) ]]; then host=${BASH_REMATCH[2]}; fi
