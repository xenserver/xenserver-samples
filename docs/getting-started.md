# Getting started

[Guide](README.md) · [Workflow examples](workflows/README.md)

## What you can do

Enumerate hosts and VMs, create and start VMs, attach storage and networks, snapshot and migrate,
configure high availability, apply updates, manage users, and subscribe to a live stream of changes. The
API is the single source of truth for a pool's configuration and runtime state, so anything the pool
knows about, you can read and (with the right role) change.

## Pick your language

Bindings are provided for **C#**, **Python**, **Java**, **Go** and **PowerShell** (the
`XenServerPSModule`, which wraps the .NET binding), plus the **`xe`** command-line tool. Every binding
exposes the same object model and the same messages; only the naming conventions differ, so an example
in one language reads the same as in another. The [workflow examples](workflows/README.md) show every
task in all of them side by side, so you can read the one you know and write the one you need. (A C
binding also exists, but is deprecated.)

## Run your first example

Use a **test pool**, not production: several examples change pool-wide state. Build the language you
want as its README describes ([C#](../csharp), [Java](../java), [PowerShell](../powershell),
[Python](../python), [Go](../go), [xe CLI](../cli)), then run the
[Connect & inventory](workflows/connect-inventory.md) example against your pool's coordinator:

```
<program> connect-inventory https://<coordinator> <username> <password>
```

You'll log in, read the pool name, and list the hosts and VMs: the "hello world" of the API, and the
starting point for every other example. Every example takes the same arguments, plus `key=value`
overrides for the objects it acts on (for example `source_vm=my-vm`).

## The shape of every program

Whatever the task, the outline is the same three steps:

1. **Open a session.** Point the binding at the pool's coordinator, accept its certificate (hosts ship
   with a self-signed one by default), and log in with your credentials and a client identifier. You get
   back a session that the binding passes on every call. See [Connecting](workflows/connecting.md).
2. **Do the work.** Read records, call messages, drive tasks; the examples show the idiom for each.
3. **Log out.** Sessions consume server resources, so release the session when you're done (in a
   `finally` block, so it happens even on error). Long-running clients keep one session open and reuse it.

[Core concepts](concepts.md) covers the handful of ideas (records, references, tasks and events) that
make every class read the same way.

## Pools and the coordinator

Hosts are grouped into a pool, with one host acting as the coordinator. Always connect to the
coordinator: if you connect to a member host, login is rejected with `HOST_IS_SLAVE` naming the
coordinator's address, and your client should reconnect there. The examples' connect helpers do this
for you.
