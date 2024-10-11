# XenServer PowerShell Module usage examples

## Overview

- [AutomatedTestCore.ps1](AutomatedTestCore.ps1): Shows how to log in to a host,
  create a storage repository and a VM, and perform various powercycle operations.

- [Updates.ps1](Updates.ps1): Shows how to configure a pool running XenServer 8
    (or greater) to synchronize with a Continuous Delivery Channel (CDN), view
    available updates and post-update tasks, and apply these updates on the
    pool's servers.

- [VmExportImport.ps1](VmExportImport.ps1): Shows how to log in to a host, create
    a VM, and export it to an .XVA package on the local machine. Then, import
    a VM from a locally stored .XVA package.

- [Metrics.ps1](Metrics.ps1): Shows how to log in to a host, and retrieve
    operational metrics.

- [UpdatesLegacy.ps1](UpdatesLegacy.ps1): Shows how to upload an update to a server
    running Citrix Hypervisor 8.2 CU1.
