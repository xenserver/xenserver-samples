# libxenserver usage examples

## Overview

The following simple examples are included in this repository:

-  `test_enumerate`: Shows how to enumerate the various API objects.

-  `test_event_handling`: Shows how to listen for events on a connection.

-  `test_get_records`: Shows how to obtain information on API objects such as
    hosts, VMs, and storage repositories.

-  `test_failures`: Shows how to translate between error strings and
    `enum_xen_api_failure`.

-  `test_vm_async_migrate`: Shows how to use asynchronous API calls to migrate
    running VMs from a supporter host to the pool coordinator.

-  `test_vm_ops`: Shows how to query the capabilities of a host, create a VM,
    attach a fresh blank disk image to the VM, and then perform various powercycle
    operations.

## Dependencies

The examples need `libxenserver` which is dependent upon the
[XML toolkit](http://xmlsoft.org) from the GNOME project, by Daniel Veillard, et
al. This is packaged as `libxml2-devel` on CentOS and `libxml2-dev` on Debian.

The examples are dependent also upon [curl](http://curl.haxx.se), by Daniel
Stenberg, et al. It is packaged as `libcurl-devel` on CentOS and `libcurl3-dev`
on Debian. You may choose to use `curl` in your application, just as we have for
these test programs, though it is not required to do so, and you may use a
different network layer if you prefer.

## How to compile

Once you have installed libxenserver, run `make` in this folder.

To run any of the tests, for example the `test_vm_ops`, type:

```
./test_vm_ops <url> <sr-name> <username> <password>
```

The `<url>` should be of the form: https://hostname.domain/

You can obtain a suitable `<sr-name>` by running `xe sr-list` on the host.
