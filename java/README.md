# XenServer Java examples

This folder holds the Java version of every workflow example ([the full list](../README.md#workflow-examples))
except `trace-api-calls` (the Java SDK cannot add a header to its requests), as a Maven project with one
class per workflow, in a package per area:

```
java/src/main/java/com/xenserver/samples/
  gettingstarted/ConnectInventory.java, Events.java, ErrorHandling.java, ...
  virtualmachines/CreateVm.java, CloneVm.java, SnapshotRevert.java, ...
  storage/  networking/  migration/  hostsandpools/  updates/  ...
  PoolConnection.java   connecting to a pool (used by every workflow)
  Helpers.java          small helpers several workflows share (find by name, clean up, ...)
  Workflows.java        the command-line dispatcher that runs any workflow by name
```

## Build and run

You need Java 11 or later and Maven. The SDK jar is not published to Maven Central, so install it into
your local repository first, then build and run:

```
mvn install:install-file -Dfile=xen-api-<version>.jar -DgroupId=com.xenserver -DartifactId=xen-api -Dversion=<version> -Dpackaging=jar
mvn compile exec:java -Dxenapi.version=<version> -Dexec.args="connect-inventory https://xenserver root <password>"
```

`PoolConnection` accepts the host's self-signed certificate, so no keystore setup is needed.

## Use a workflow in your own code

Each workflow is a class with a self-contained `run` method you can copy into your own code, together
with `PoolConnection` (and any helper from `Helpers` it uses). Its Javadoc describes what it does and
shows how to call it, e.g.:

```java
ConnectInventory.run("https://xenserver", "root", password);
```
