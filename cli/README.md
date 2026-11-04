# XenServer CLI (xe) examples

This folder holds the `xe` version of every workflow example ([the full list](../README.md#workflow-examples)),
written entirely with `xe` commands: the same commands you would type at a host's console. One file per
workflow, in a folder per area:

```
cli/
  getting-started/connect-inventory.sh, events.sh, error-handling.sh, trace-api-calls.sh, ...
  virtual-machines/create-vm.sh, clone-vm.sh, snapshot-revert.sh, ...
  storage/  networking/  migration/  hosts-and-pools/  updates/  ...
  connection.sh    where xe sends its commands (the xe wrapper every workflow uses)
  helpers.sh       small helpers several workflows share (reading --minimal output, clean up, ...)
  workflows.sh     loads them all and runs any workflow by name
```

## Run

You need bash and an `xe` client. On Windows, use Git Bash and the `xe.exe` that ships with
XenCenter. Point `XE_EXE` at `xe` if it is not on your `PATH`:

```
export XE_EXE="/c/Program Files (x86)/XenServer/XenCenter/xe.exe"
./workflows.sh connect-inventory https://xenserver root <password>
```

The script talks to the host on port 443 over TLS, the `xe` default. If the URL names any other port,
it reaches the CLI over plain HTTP on the next port up, which is how test endpoints usually serve it.

## Use a workflow in your own scripts

Each workflow is a shell function. The comment at the top of its file describes what it does, how to
run it and the `key=value` arguments it takes. To use one in your own script, copy it along with
`connection.sh` (where the connection details go) and any helper from `helpers.sh` it calls.
