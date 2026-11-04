# XenServer SDK — a short guide

The XenServer SDK is a set of language bindings for the XenServer Management API, the "XenAPI": the same
remote API XenCenter uses to manage a pool of XenServer hosts. If you can do it in XenCenter, you can do
it from code.

This guide is deliberately short. It gives you enough to get oriented, then hands you to the
[workflow examples](workflows/README.md): real, runnable code for 90 common tasks, each in C#, Python,
Java, Go, PowerShell and the `xe` CLI, side by side, with the output of running it.

1. [Getting started](getting-started.md): pick a language, run your first example, the shape of every program.
2. [Core concepts](concepts.md): records and references, accessors, messages, tasks and events.
3. [Errors](errors.md): what a failed call looks like in each binding.
4. [Moving data over HTTP](http.md): imports, exports, updates, performance data.
5. [Conventions and extensions](extensions.md): `other_config`, tags, API versions.
6. [The xe command line](cli.md).

Then browse the [workflow examples](workflows/README.md), starting with [Connecting](workflows/connecting.md).

For the full API reference and SDK downloads, see the
[XenServer SDK Guide](https://docs.xenserver.com/en-us/xenserver/8/developer/sdk-guide).
