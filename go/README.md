# XenServer SDK for Go usage examples

## Overview

The following simple examples are included in this repository:

-  `base_test`: Create the basic session, login and logout.

-  `event_test`: Listens for events on a connection and prints each event out 
    as it is received.

-  `get_all_records_test`: Retrieves the records for all types of objects.

-  `network_test`: Create and destroy a new external network.

-  `pool_test`: Add a server to a pool and then eject it.

-  `session_test`: Set up session over https protocol with or without certificate.

-  `sr_nfs_test`: Creates a shared NFS SR.

-  `sr_test`: Performs various base SR tests, including creating
    a dummy SR.

-  `vm_create_and_destroy_test`: Create and destroy a VM on the default SR with a network and DVD drive. Repeat using asynchronous calls.

-  `vm_power_cycle_test`: Takes a VM through the various lifecycle states. Requires a 
    shutdown VM with tools installed.

-  `vm_snapshot_test`: Create, revert and destroy VM snapshot. Repeat using asynchronous calls.


## Dependencies

Install Go 1.22 or above on the runnning environment.

Prepare the local XenServer module for Go. 
- Download the XenServer SDK zip package and unzip
- Create goSDK directory under ./XenServerSamples/go/
- Copy all source files under XenServer-SDK/XenServerGo/src/ to XenServerSamples/go/goSDK folder

Run the commands as follows:
```
go get all
go get -u all
go mod tidy
```

## How to run the examples

The test runs with nine parameters:

```
<ip>           : the URL of the form https://ip[:port] pointing at the server
<username>     : the username of the host (e.g. root)
<password>     : the password of the host
<ca_cert_path> : the CA certificate file path for the host
<nfs_server>   : the ip address pointing at the nfs server
<nfs_path>     : the nfs server path
<ip1>          : the URL of the form https://ip[:port] pointing at the supporter server
<username1>    : the username of the supporter host (e.g. root)
<password1>    : the password of the supporter host
```

Run it as follows:

```
go test -ip="1.1.1.1" -username="user" -password="passwd" -ca_cert_path="/ca.pem" -nfs_server="1.1.1.2" -nfs_path="/nfs" -ip1="1.1.1.3" -username1="user1" -password1="passwd1" -v
```
