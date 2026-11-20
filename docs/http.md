# Moving data over HTTP

[Guide](README.md) · [Workflow examples](workflows/README.md)

A few operations move bulk data, and are done over plain HTTP(S) to the host rather than through the RPC
API. They are still authenticated by the same session.

## What goes over HTTP

Importing and exporting VMs and disk images, uploading updates, downloading status reports and pulling
performance data are done by `GET`/`PUT` to well-known paths on the host, passing the session (and, for
long transfers, a task to track it) as query parameters. These transfers stream large payloads that would
be impractical as RPC arguments.

## The usual pattern

A typical flow makes an RPC call to prepare or authorize the transfer, then performs the HTTP request to
move the bytes, then reads the outcome from the task. For example:

- [Export and import a VM](workflows/export-import-vm.md): creates a task, streams the VM out and back
  in, and reads the imported VM's reference from the task's result (the HTTP response doesn't carry it).
- [Read RRD performance metrics](workflows/rrd-metrics.md): pulls a host's performance archives over the
  performance-data endpoint and parses them.
- [Server status report](workflows/server-status-report.md) and
  [Back up a host's configuration](workflows/backup-host-config.md): download over HTTP.
