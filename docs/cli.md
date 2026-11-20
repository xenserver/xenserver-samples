# The xe command line

[Guide](README.md) · [Workflow examples](workflows/README.md)

The same operations are available from the `xe` command-line interface, which is ideal for scripting
and quick investigation from a shell.

## Command shape

Commands follow `xe <class>-<operation>` with `name=value` arguments, for example `xe vm-list` or
`xe vm-start uuid=<uuid>`; nested map entries are `name:key=value` (such as
`device-config:server=…`). List commands accept filters, and `xe <class>-param-list uuid=…` shows an
object's fields. Add `--minimal` to get a bare, comma-separated result that's easy to slice in a script.

## In a script

`xe` prints a failure on standard output and exits non-zero. Inside `$(...)` the error text would land
in your variable, so check the exit status (the example script's `xe` wrapper sends a failing command's
output to standard error instead). From Git Bash on Windows, arguments that look like paths
(`serverpath=/export`) are rewritten into Windows paths unless `MSYS_NO_PATHCONV=1` is set.

## When to use it

The CLI is perfect for one-off tasks and shell scripts. For anything structured (reacting to events,
handling errors programmatically, or building a tool) reach for one of the language bindings. The
[workflow examples](workflows/README.md) show every task done entirely from the shell too.
