# XenServer SDK samples

Ready-to-run code for managing [XenServer](https://www.xenserver.com/) pools with the XenServer SDK.

Whether you want to list your VMs, automate a rolling update or wire XenServer into your own tooling,
there's an example here to start from. Each one is written for **PowerShell and the `xe` command line,
and in Python, C#, Go and Java**, so you can read it in the language you know and use it in the language
you need.

The samples are a companion to the
[XenServer SDK Guide](https://docs.xenserver.com/en-us/xenserver/developer/sdk-guide), which has the
full API reference and the SDK downloads.

## What's inside

- **Workflow examples:** common pool-management tasks, from logging in to disaster recovery. Each
  is implemented in all six languages, except tracing API calls, which the Java SDK cannot do.
- **[Browsable docs](docs/workflows/README.md):** one page per workflow, with the code in every language
  side by side and the output of running it.
- **[A short guide to the API](docs/README.md):** sessions, records, tasks, events and errors, enough
  to get you oriented.

## Quick start

1. **Pick a language** and set it up as its README describes. Mostly that means getting the SDK binding
   for your language from the
   [XenServer SDK Guide](https://docs.xenserver.com/en-us/xenserver/developer/sdk-guide).
2. **Run your first workflow**, `connect-inventory`, against your pool's coordinator. It logs in and
   lists the pool's hosts and VMs:

   | Language | From its folder |
   |---|---|
   | [PowerShell](powershell) | `pwsh -File workflows.ps1 connect-inventory https://<coordinator> root <password>` |
   | [xe CLI](cli) | `./workflows.sh connect-inventory https://<coordinator> root <password>` |
   | [Python](python) | `python workflows.py connect-inventory https://<coordinator> root <password>` |
   | [C#](csharp) | `dotnet run -- connect-inventory https://<coordinator> root <password>` |
   | [Go](go) | `go run . connect-inventory https://<coordinator> root <password>` |
   | [Java](java) | `mvn compile exec:java -Dxenapi.version=<version> -Dexec.args="connect-inventory https://<coordinator> root <password>"` |

3. **Explore.** Browse the [workflow examples](docs/workflows/README.md) and run any of them the same
   way.

> **Use a test pool, not production.** Several workflows change pool-wide state: they restart hosts,
> rotate the pool secret, enable HA, apply updates and more. See [Before you run them](#before-you-run-them).

## The workflows

| Area | For example |
|---|---|
| [Getting started](docs/workflows/README.md#getting-started) | Connect and take inventory, run a task, handle errors, follow events, trace calls |
| [Virtual machines](docs/workflows/README.md#virtual-machines) | Create, clone, snapshot, add disks, vTPM, vGPU, USB passthrough |
| [Migration](docs/workflows/README.md#migration) | Live-migrate a VM, move its disks to another SR |
| [Storage](docs/workflows/README.md#storage) | NFS, SMB, iSCSI, Fibre Channel and ISO SRs; copying disk contents; changed block tracking |
| [Networking](docs/workflows/README.md#networking) | Networks, NIC bonds, virtual network interfaces |
| [Hosts & pools](docs/workflows/README.md#hosts--pools) | Maintenance mode, HA, certificates, SSH access, pool membership, performance metrics |
| [Updates](docs/workflows/README.md#updates) | Configure update repositories (CDN or offline), apply updates, rolling pool update |
| [Organization & metadata](docs/workflows/README.md#organization--metadata) | Tags, folders, custom fields |
| [Security & access](docs/workflows/README.md#security--access) | Active Directory users, roles, Secure Boot certificates |
| [Disaster recovery](docs/workflows/README.md#disaster-recovery) | Replicate pool metadata, and fail over to a disaster recovery site from the storage array's replica |

The [workflow docs](docs/workflows/README.md) list them all, with a one-line description of each.

## How the examples work

Every workflow follows the same pattern, so once you've read one you can read them all:

- **It's self-contained.** Each workflow is a single function in a file of its own, grouped by area. It
  opens its own session, does one job, cleans up after itself and prints `OK: <workflow>` when it
  succeeds. To use one in your own code, copy it together with the connection helper and any shared
  helper it calls; its documentation comment shows the call.
- **It connects to any pool member.** The shared connect helper accepts a host's self-signed
  certificate without checking it, which suits a test pool; in production, check it instead (give the
  hosts a certificate from a CA you trust, or trust the pool's own certificate explicitly). If you point
  it at a pool member rather than the coordinator, it follows the `HOST_IS_SLAVE` redirect.
- **It runs from the command line.** Each language's dispatcher (`workflows.ps1`, `workflows.sh`, `workflows.py`, ...)
  runs any workflow:

  ```
  <program> <workflow> <url> <username> <password> [key=value ...]
  ```

  `key=value` arguments point a workflow at your own objects and servers, for example
  `source_vm=my-vm`, `sr_name=my-shared-sr` or `nfs_server=… nfs_path=…`. Each language's dispatcher
  lists the defaults. The one exception is `cross-pool-copy-vm`, which takes the destination pool's URL
  as an extra argument after the password.

## Before you run them

The workflows are written for a **test pool** of at least two hosts: several move VMs between hosts,
restart a host or hand the coordinator role to another. By default they look for these objects by name,
so create them or override the names with `key=value` arguments:

- a running VM **`web-01`** with a guest OS and the XenServer VM Tools. Workflows that need guest
  cooperation, such as suspend and live migration, work on a copy of it (`source_vm`).
- a halted VM **`db-01`**
- a shared SR named **`Shared NFS`**
- the **`Rocky Linux 8`** template

A few also need a second halted VM, a halted VM that boots in UEFI mode, or an ISO library with an ISO
in it. Others need particular storage, hardware or a second pool. Each workflow's page in the
[workflow docs](docs/workflows/README.md) says what it needs under **Requires**.

The storage workflows point at placeholder servers in the `192.0.2.0/24` documentation range, so
override them with your own. Workflows that create an SR on a LUN format that LUN.

## Contributing

Contributions are welcome! Fork the repository and open a pull request; see [CONTRIBUTING](CONTRIBUTING.md)
for the details. Questions or feedback about the samples are welcome too, on the
[issues](https://github.com/xenserver/xenserver-samples/issues) page. If you have a support agreement, you
can also raise questions through your usual XenServer support channel.

## License

BSD 2-Clause. See [LICENSE](LICENSE).
