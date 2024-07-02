# XenAPI.py usage examples

## Overview

The following Python examples are included in this repository:

- `exportimport.py` — Demonstrate how to
  - export raw disk images
  - import raw disk images
  - connect an export to an import to copy a raw disk image

-  `fixpbds.py` - reconfigures the settings used to access shared storage.

-  `install.py` - installs a Debian VM, connects it to a network, starts it up and 
    waits for it to report its IP address.

-  `license.py` - uploads a fresh license to a XenServer host.

-  `permute.py` - selects a set of VMs and uses live migration to move them
    simultaneously among hosts.

-  `powercycle.py` - selects a set of VMs and powercycles them.

-  `provision.py`: - parses/regenerates the "disk provisioning" XML contained 
    within templates

-  `shutdown.py`: - shows how to prepare and shutdown a host.

-  `vm_start_async.py` - shows how to invoke operations asynchronously.

-  `watch-all-events.py` - registers for all events and prints details
    when they occur.

## How to run the scripts

Each script requires 3 command line arguments:

```
URL       : a URL of the form https://host[:port] pointing at the server
username  : a valid user on the server (e.g. root)
password  : the user's password
```

For example:

```
./install.py https://myhost.mydomain.com root letmein
```
