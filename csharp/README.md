# XenServer.NET (C#) examples

This folder holds the C# version of every workflow example ([the full list](../README.md#workflow-examples)),
one file per workflow, grouped in a folder per area:

```
csharp/
  GettingStarted/ConnectInventory.cs, Events.cs, ErrorHandling.cs, TraceApiCalls.cs, ...
  VirtualMachines/CreateVm.cs, CloneVm.cs, SnapshotRevert.cs, ...
  Storage/  Networking/  Migration/  HostsAndPools/  Updates/  ...
  Connection.cs    connecting to a pool (used by every workflow)
  Helpers.cs       small helpers several workflows share (find by name, clean up, ...)
  Program.cs       the command-line dispatcher that runs any workflow by name
```

## Build and run

The project references the XenServer.NET NuGet package, which the SDK ships in its `XenServer.NET` folder.
Add that folder as a package source once, then build and run it with the .NET 8 SDK (or open
`XenServerWorkflows.csproj` in Visual Studio):

```
dotnet nuget add source <path-to-SDK>/XenServer.NET -n xenserver-sdk
dotnet run -- connect-inventory https://xenserver root <password>
```

## Use a workflow in your own code

Each workflow is a self-contained static method you can copy into your own code, together with
`Connection.cs` (and any helper from `Helpers.cs` it uses). Its documentation comment describes what it
does, and the `<example>` shows how to call it, e.g.:

```csharp
Workflows.ConnectInventory("https://xenserver", "root", password);
```
