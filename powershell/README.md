# XenServer PowerShell Module usage examples

## Overview

- [AutomatedTestCore.ps1](AutomatedTestCore.ps1): Shows how to log in to a host,
  create a storage repository and a VM, and perform various powercycle operations.

- [SmartConnect.ps1](SmartConnect.ps1): Shows how to handle the error when
    attempting to connect to a supporter server, identify the pool coordinator,
    and connect to it instead.

- [Updates.ps1](Updates.ps1): Shows how to configure a pool running XenServer 8
    (or greater) to synchronize with a Continuous Delivery Channel (CDN), view
    available updates and post-update tasks, and apply these updates on the
    pool's servers.

- [UpdatesOffline.ps1](UpdatesOffline.ps1): Shows how to configure an air-gapped
    pool running XenServer 8 (or greater) for upload and installation of update
    bundles, view available updates and post-update tasks, and apply these updates
    on the pool's servers.

- [VmExportImport.ps1](VmExportImport.ps1): Shows how to log in to a host, create
    a VM, and export it to an .XVA package on the local machine. Then, import
    a VM from a locally stored .XVA package.

- [Metrics.ps1](Metrics.ps1): Shows how to log in to a host, and retrieve
    operational metrics.

- [UpdatesLegacy.ps1](UpdatesLegacy.ps1): Shows how to upload and install an 
    update to a server running Citrix Hypervisor 8.2 CU1.
