# XenServerJava usage examples

This folder contains of a number of test programs that can be used as pedagogical
examples accompanying XenServerJava (com.xenserver.xen-api). They are
structured as a Maven project.

## Dependencies

This code depends on XenServerJava, which in turns depends upon Apache XML-RPC
by the Apache Software Foundation, licensed under the Apache Software License 2.0.

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
