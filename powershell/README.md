# XenServer PowerShell examples

This folder holds the PowerShell version of every workflow example ([the full list](../README.md#workflow-examples)),
written with the SDK module's cmdlets: one script per workflow function, in a folder per area:

```
powershell/
  GettingStarted/Invoke-ConnectInventory.ps1, Invoke-Events.ps1, Invoke-TraceApiCalls.ps1, ...
  VirtualMachines/Invoke-CreateVm.ps1, Invoke-CloneVm.ps1, Invoke-SnapshotRevert.ps1, ...
  Storage/  Networking/  Migration/  HostsAndPools/  Updates/  ...
  Connection.ps1   connecting to a pool (used by every workflow)
  Helpers.ps1      small helpers several workflows share (find by name, clean up, ...)
  workflows.ps1    loads them all and runs any workflow by name
```

## Run

Copy the `XenServerPSModule` folder for your PowerShell from the SDK into a folder on
`$env:PSModulePath`: `XenServerPowerShell/PowerShell_7` for PowerShell 7 (`pwsh`), or
`XenServerPowerShell/PowerShell_51` for Windows PowerShell 5.1 (`powershell`). Then:

```
pwsh -File workflows.ps1 connect-inventory https://xenserver root <password>
```

## Use a workflow in your own scripts

Each workflow is a self-contained function you can copy into your own scripts, together with
`Connection.ps1` (and any helper from `Helpers.ps1` it uses). Its comment-based help describes what it
does and shows how to call it:

```powershell
. .\Connection.ps1
. .\GettingStarted\Invoke-ConnectInventory.ps1
Get-Help Invoke-ConnectInventory -Full
Invoke-ConnectInventory -Url https://xenserver -UserName root -Password $password
```
