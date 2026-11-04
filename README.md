# XenServer SDK samples

Ready-to-run code for managing [XenServer](https://www.xenserver.com/) pools with the XenServer SDK.

Whether you want to list your VMs, automate a rolling update or wire XenServer into your own tooling,
there's an example here to start from. Each one is written in **C#, Python, Java, Go and PowerShell, and
for the `xe` command line**, so you can read it in the language you know and use it in the language you
need.

The samples are a companion to the
[XenServer SDK Guide](https://docs.xenserver.com/en-us/xenserver/8/developer/sdk-guide), which has the
full API reference and the SDK downloads.

## What's inside

- **94 workflow examples:** common pool-management tasks, from logging in to disaster recovery. Each
  is implemented in all six languages, except tracing API calls, which the Java SDK cannot do.
- **[Browsable docs](docs/workflows/README.md):** one page per workflow, with the code in every language
  side by side and the output of running it.
- **[A short guide to the API](docs/README.md):** sessions, records, tasks, events and errors, enough
  to get you oriented.

## Quick start

1. **Pick a language** and set it up as its README describes. Mostly that means getting the SDK binding
   for your language from the
   [XenServer SDK Guide](https://docs.xenserver.com/en-us/xenserver/8/developer/sdk-guide).
2. **Run your first workflow**, `connect-inventory`, against your pool's coordinator. It logs in and
   lists the pool's hosts and VMs:

   | Language | From its folder |
   |---|---|
   | [Python](python) | `python workflows.py connect-inventory https://<coordinator> root <password>` |
   | [C#](csharp) | `dotnet run -- connect-inventory https://<coordinator> root <password>` |
   | [Java](java) | `mvn compile exec:java -Dxenapi.version=<version> -Dexec.args="connect-inventory https://<coordinator> root <password>"` |
   | [Go](go) | `go run . connect-inventory https://<coordinator> root <password>` |
   | [PowerShell](powershell) | `pwsh -File workflows.ps1 connect-inventory https://<coordinator> root <password>` |
   | [xe CLI](cli) | `./workflows.sh connect-inventory https://<coordinator> root <password>` |

3. **Explore.** Browse the [workflow examples](docs/workflows/README.md) and run any of them the same
   way.

> **Use a test pool, not production.** Several workflows change pool-wide state: they restart hosts,
> rotate the pool secret, enable HA, apply updates and more. See [Before you run them](#before-you-run-them).

## The workflows

| Area | Workflows | For example |
|---|---|---|
| [Getting started](docs/workflows/README.md#getting-started) | 6 | Connect and take inventory, run a task, handle errors, follow events, trace calls |
| [Virtual machines](docs/workflows/README.md#virtual-machines) | 26 | Create, clone, snapshot, add disks, vTPM, vGPU, USB passthrough |
| [Migration](docs/workflows/README.md#migration) | 2 | Live-migrate a VM, move its disks to another SR |
| [Storage](docs/workflows/README.md#storage) | 15 | NFS, SMB, iSCSI, Fibre Channel and ISO SRs; copying disk contents; changed block tracking |
| [Networking](docs/workflows/README.md#networking) | 4 | Networks, NIC bonds, virtual network interfaces |
| [Hosts & pools](docs/workflows/README.md#hosts--pools) | 30 | Maintenance mode, HA, certificates, SSH access, pool membership |
| [Updates](docs/workflows/README.md#updates) | 4 | Configure update repositories (CDN or offline), apply updates, rolling pool update |
| [Organization & metadata](docs/workflows/README.md#organization--metadata) | 3 | Tags, folders, custom fields |
| [Security & access](docs/workflows/README.md#security--access) | 3 | Active Directory users, roles, Secure Boot certificates |
| [Disaster recovery](docs/workflows/README.md#disaster-recovery) | 1 | Replicate pool metadata and recover VMs on a standby pool |

The full list, with a one-line description of each, is in [workflows.json](workflows.json).

## How the examples work

Every workflow follows the same pattern, so once you've read one you can read them all:

- **It's self-contained.** Each workflow is a single function in a file of its own, grouped by area. It
  opens its own session, does one job, cleans up after itself and prints `OK: <workflow>` when it
  succeeds. Copy it into your own code as it is: its documentation comment shows the call.
- **It connects the way XenCenter does.** The shared connect helper accepts a host's self-signed
  certificate. If you point it at a pool member rather than the coordinator, it follows the
  `HOST_IS_SLAVE` redirect.
- **It runs from the command line.** Each language's dispatcher (`workflows.py`, `workflows.ps1`, ...)
  runs any workflow:

  ```
  <program> <workflow> <url> <username> <password> [key=value ...]
  ```

  `key=value` arguments point a workflow at your own objects and servers, for example
  `source_vm=my-vm`, `sr_name=my-shared-sr` or `nfs_server=… nfs_path=…`. Each language's dispatcher
  lists the defaults. The one exception is `cross-pool-copy-vm`, which takes the destination pool's URL
  as an extra argument after the password.

## Before you run them

The workflows are written for a **test pool**. By default they look for these objects by name, so
create them or override the names with `key=value` arguments:

- a running VM **`web-01`** with a guest OS and the XenServer VM Tools. Workflows that need guest
  cooperation, such as suspend, checkpoint and live migration, work on a copy of it (`source_vm`).
- a halted VM **`db-01`**
- a shared SR named **`Shared NFS`**
- the **`Rocky Linux 8`** template

The storage workflows point at placeholder servers in the `192.0.2.0/24` documentation range, so
override them with your own. Workflows that create an SR on a LUN format that LUN.

## More in this repository

- **[Working with performance metrics](misc/using_rrd.md):** how to retrieve and use XenServer's
  operational metrics (RRDs).

## Contributing

Contributions are welcome! Fork the repository and open a pull request; see [CONTRIBUTING](CONTRIBUTING.md)
for the details. Questions about the samples are welcome too, on the
[issues](https://github.com/xenserver/xenserver-samples/issues) page.

## License

BSD 2-Clause. See [LICENSE](LICENSE).
