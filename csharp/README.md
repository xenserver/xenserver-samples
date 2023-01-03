# XenServer.NET usage examples

## How to run the examples

Open `XenSdkSample.sln` inside Visual Studio 2022 and compile the solution.

The solution project is a console application expecting three parameters:

```
<host>     : a URL of the form https://host[:port] pointing at the server
<username> : a valid user on the server (e.g. root)
<password> : the user's password
```

Run it as follows:

```
.\XenSdkSample.exe https://myhost.mydomain.com:443 root letmein
```