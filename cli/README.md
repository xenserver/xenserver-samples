# XenServer CLI (xe) examples

This folder holds the `xe` version of every workflow example ([the full list](../README.md#the-workflows)),
written entirely with `xe` commands: the same commands you would type at a host's console. One file per
workflow, in a folder per area:

```
cli/
  getting-started/connect-inventory.sh, events.sh, error-handling.sh, trace-api-calls.sh, ...
  virtual-machines/create-vm.sh, clone-vm.sh, snapshot-revert.sh, ...
  storage/  networking/  migration/  hosts-and-pools/  updates/  ...
  connection.sh    where xe sends its commands (remote_xe, the xe wrapper every workflow uses)
  helpers.sh       small helpers several workflows share (reading --minimal output, clean up, ...)
  workflows.sh     loads them all and runs any workflow by name
```

## Run

You need bash and an `xe` client. On Windows, use Git Bash and the Windows `xe.exe`. Point
`XE_EXE` at `xe` if it is not on your `PATH`:

```
export XE_EXE="/c/Program Files (x86)/XenServer/XenCenter/xe.exe"
./workflows.sh connect-inventory https://xenserver root <password>
```

The script talks to the host on port 443, the `xe` default, or on the port the URL names, over TLS. The
Windows `xe.exe` is the exception: it uses TLS only on port 443, and plain HTTP on any other port.

The workflows call `remote_xe`, not `xe`: it runs your `xe` client against the pool with its address
(`-s`) and your credentials added, so it works from any machine, not only a host's own console. The user
name and password go to `xe` in a temporary file only you can read (`-pwf`, the user name on its first line
and the password on its second), removed when the script ends, rather than on its command line, where
other users could see them. The Windows `xe.exe` has no `-pwf`, so there they are passed with `-u` and
`-pw`.

## Use a workflow in your own scripts

Each workflow is a shell function. The comment at the top of its file describes what it does, how to
run it and the `key=value` arguments it takes. To use one in your own script, copy it along with
`connection.sh` (where the connection details go) and any helper from `helpers.sh` it calls.
