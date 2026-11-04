# Core concepts

[Guide](README.md) · [Workflow examples](workflows/README.md)

A few concepts recur throughout the API; once they click, every class reads the same way. Each is shown
end to end in an example you can run.

## Records and references

Every object has an opaque **reference** and a **record** (its fields). Fields that point at other objects
hold references (or lists or maps of them); a null reference is `OpaqueRef:NULL`. You navigate the model
by following references. The quickest way to see the whole shape is `get_all_records` on any class, which
returns a map of reference to record; that's what [Connect & inventory](workflows/connect-inventory.md)
does. References are per-session: to keep a durable handle to an object, store its `uuid` and resolve it
later with `get_by_uuid` (see [Look up an object by UUID](workflows/find-by-uuid.md)).

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
