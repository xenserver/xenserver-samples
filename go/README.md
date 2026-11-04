# XenServer Go examples

This folder holds the Go version of every workflow example ([the full list](../README.md#workflow-examples)),
one file per workflow, all in one `main` package:

```
go/
  connect_inventory.go, create_vm.go, snapshot_revert.go, trace_api_calls.go, ...
  connection.go    connecting to a pool (used by every workflow)
  helpers.go       small helpers several workflows share (find by name, clean up, ...)
  main.go          the command-line dispatcher that runs any workflow by name
  goSDK/           the SDK's Go binding (you copy it here; see below)
```

## Build and run

You need Go 1.27 or later. The SDK's Go binding is not published as a module: copy
`XenServerGo/src` from the SDK into `goSDK/` here (`go.mod` points at it), then:

```
go run . connect-inventory https://xenserver root <password>
```

## Use a workflow in your own code

Each workflow is a self-contained function you can copy into your own code, together with
`connection.go` (and any helper from `helpers.go` it uses). Its doc comment describes what it does and
shows how to call it, e.g.:

```go
connectInventory("https://xenserver", "root", password)
```
