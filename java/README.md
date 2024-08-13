# XenServerJava usage examples

This folder contains of a number of test programs that can be used as pedagogical
examples accompanying XenServerJava (com.xenserver.xen-api). They are
structured as a Maven project.

## Overview

Running the main file `RunTests` runs a series of examples included in the 
same directory:

-  `AddNetwork`: Adds a new internal network not attached to any NICs.

-  `AsyncVMCreate`: Makes asynchronously a new VM from a built-in template, 
    starts, and stops it.

-  `CreateVM`: Creates a VM on the default SR with a network and DVD drive.

-  `EventMonitor`: Listens for events on a connection and prints each event out 
    as it is received.

-  `GetVariousRecords`: Retrieves the records for various types of objects.

-  `SessionReuse`: Shows how a Session object can be shared among multiple Connections.

-  `SharedStorage`: Creates a shared NFS SR.

-  `StartAllVMs`: Connects to a host and tries to start each VM on it.

-  `VMlifecycle`: Takes a VM through the various lifecycle states. Requires a 
    shutdown VM with tools installed.

-  `VdiAndSrOps`: Performs various SR and VDI tests, including creating
    a dummy SR.

## Dependencies

This code depends on XenServerJava, which in turns depends upon Apache XML-RPC
by the Apache Software Foundation, licensed under the Apache Software License 2.0.


If you have the jar, you can install it using the Maven CLI:

```bash
mvn install:install-file -Dfile=".\xen-api-XX.YY.ZZ.jar" -DgroupId="com.xenserver" -DartifactId=xen-api -Dversion="XX.YY.ZZ" -Dpackaging=jar
```

## How to run the tests

Once you compile the project run:

```
RunTests <host> <username> <password> [nfs server] [nfs path]
```

Before running, you may need to perform these steps:

1. Run the following command on the server you want to connect to:
   ```
   openssl x509 -in /etc/xensource/xapi-ssl.pem -pubkey -out serverpub.pem
   ```

2. Copy the public key `serverpub.pem` to your client machine.

3. To convert the public key into a form that Java's keytool can understand, run:
   ```
   openssl x509 -inform PEM -outform DER -in serverpub.pem -out serverpub.jks
   ```

4. Run keytool (found in Java's bin directory) as follows:
   ```
   keytool -importcert -file serverpub.jks -alias <hostname> [-keystore <keystore_location>]
   ```

5. To tell the JVM the location and password of your keystore, run it with the
   additional parameters:
   ```
   -Djavax.net.ssl.trustStore=<keystore_location> -Djavax.net.ssl.trustStorePassword=<keystore_password>
   ```
   For extra debug info, try:
   ```
   -Djavax.net.debug=ssl
   ```
