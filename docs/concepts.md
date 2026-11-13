# Core concepts

[Guide](README.md) · [Workflow examples](workflows/README.md)

A few concepts recur throughout the API; once they click, every class reads the same way. Each is shown
end to end in an example you can run.

## Names, UUIDs and references

An object can be identified in three ways, and each has its own job:

- **Its name** (`name_label`) is what people call it. Anyone can change it, and two objects can share
  one, so a lookup by name can find none, one or several.
- **Its UUID** (`uuid`) is permanent and unique. Use it for anything you store or log, and to let people
  pick an object when a name might be ambiguous. `get_by_uuid` turns it back into the object (see
  [Look up an object by UUID](workflows/find-by-uuid.md)).
- **Its reference** is the handle the API passes around: every call takes and returns references (they
  look like `OpaqueRef:…`). Treat them as plumbing between one call and the next. Don't show them to
  people, store them or ask anyone to type one, and don't expect a reference to mean anything to another
  pool. When you need one, get it from a name or a UUID (`get_by_name_label`, `get_by_uuid`).

How much of this you see depends on the language. The PowerShell cmdlets take the objects themselves (or
`-Uuid` and `-Name`), and `xe` works entirely with UUIDs and names. In Python, C#, Go and Java, references
are simply the values you pass from one call to the next.

## Records and references

Every object has a **record** (its fields). Fields that point at other objects hold references (or lists
or maps of them); a null reference is `OpaqueRef:NULL`. You navigate the model by following references.
The quickest way to see the whole shape is `get_all_records` on any class, which returns a map of
reference to record; that's what [Connect & inventory](workflows/connect-inventory.md) does.

## Get and set accessors

Each field has a generated `get_<field>` accessor, and writable fields also have `set_<field>`. Map
fields add `add_to_<field>` / `remove_from_<field>`, and list-valued fields add `add_<field>` /
`remove_<field>`. That is why the API lists so many messages per class: most of them are accessors that
all behave identically.

## Messages

Beyond accessors, a class exposes **messages**: the operations you can perform, such as `VM.start` or
`VM.pool_migrate`. Each takes its parameters and returns a value, and was introduced in a particular
release. Most messages take the session as their first argument; the bindings supply it for you.

## Asynchronous tasks

Long-running operations have an `Async.*` twin that returns a **task** reference immediately instead of
blocking. Poll `task.get_status` until it leaves `pending`, then read `task.get_result` (for an
object-creating call, the result is `<value>OpaqueRef:…</value>`). Prefer this for anything that copies
data, such as moving a disk: a synchronous call that runs for many minutes holds an HTTP request open
that long, and clients and networks give up on those. See
[Drive an asynchronous task](workflows/wait-for-task.md).

## Events

Rather than polling, subscribe to changes with `event.from`: the first call returns the current state as
a batch and a token; later calls with that token block until something changes and return only the
delta. This is how a management console keeps its view live without re-reading the world. See
[Event monitoring](workflows/events.md).

## Guest cooperation

Some VM operations need the guest's help, and so need a guest OS with the XenServer VM Tools (PV
drivers) running: suspend, checkpoint, live migration and clean shutdown or reboot. On a running VM
without them, these fail at once with `VM_LACKS_FEATURE`, and are missing from the VM's
`allowed_operations`. A VM freshly provisioned from a template has no OS, so the examples that need one
work on a copy of a VM that does (their `source_vm` parameter), and wait for its tools to report in.
