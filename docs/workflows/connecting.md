<!-- Generated from workflows.json, the example sources and a run of each example. Edit those, not this file. -->

# Connecting

Every workflow starts the same way: open a session to the pool's coordinator, accepting its certificate (hosts ship with a self-signed one) and logging in. If you connect to a pool member instead, login fails with `HOST_IS_SLAVE` naming the coordinator, and these helpers reconnect there, as XenCenter does.

[All workflows](README.md)

## C# (.NET)

```csharp
internal static Session Connect(string url, string user, string password)
{
    try
    {
        return Login(url, user, password);
    }
    catch (Failure f) when (f.ErrorDescription[0] == "HOST_IS_SLAVE")
    {
        // A pool member names the coordinator's address; reconnect there (assuming the coordinator
        // is up), exactly as XenCenter does when you add a member server.
        return Login($"https://{f.ErrorDescription[1]}", user, password);
    }
}

internal static Session Login(string url, string user, string password)
{
    var session = new Session(url);
    // Accept the host's self-signed certificate.
    session.JsonRpcClient.ServerCertificateValidationCallback = (req, cert, chain, errors) => true;
    session.login_with_password(user, password, "1.0", "sdk-examples");
    return session;
}
```

## Python

```python
def connect(url, username, password):
    """Open a session, skipping certificate validation for the host's self-signed cert.

    If url points at a pool *member* rather than the coordinator, login fails with HOST_IS_SLAVE
    naming the coordinator's address; we reconnect to it (assuming the coordinator is up), exactly
    as XenCenter does when you add a member server."""
    session = XenAPI.Session(url, ignore_ssl=True)
    try:
        session.login_with_password(username, password, "1.0", "sdk-examples")
    except XenAPI.Failure as e:
        if e.details[0] != "HOST_IS_SLAVE":
            raise
        session = XenAPI.Session("https://%s" % e.details[1], ignore_ssl=True)  # the coordinator
        session.login_with_password(username, password, "1.0", "sdk-examples")
    return session
```

## Java

```java
public static Connection connect(String url, String user, String password) throws Exception {
    CloseableHttpClient http = trustingHttpClient();
    try {
        return login(http, url, user, password);
    } catch (Types.HostIsSlave e) {
        // A pool member names the coordinator's address; reconnect there (assuming the coordinator
        // is up), exactly as XenCenter does when you add a member server. SDKs before CA-432633 read
        // that address as "" under JSON-RPC: say so rather than connecting to "https://".
        if (e.masterIPAddress == null || e.masterIPAddress.isEmpty())
            throw new CoordinatorUnknown(url);
        return login(http, "https://" + e.masterIPAddress, user, password);
    }
}

/**
 * HOST_IS_SLAVE from a pool member, without the coordinator's address (see connect).
 */
public static class CoordinatorUnknown extends Exception {
    CoordinatorUnknown(String url) {
        super(url + " is a pool member, and this SDK did not report the coordinator's address");
    }
}

/**
 * An HTTP client that trusts the host's self-signed certificate. (Apache HttpClient 5 uses its own SSL
 * context, so we configure it here rather than relying on JVM-wide defaults.)
 */
public static CloseableHttpClient trustingHttpClient() throws Exception {
    SSLContext ssl = SSLContexts.custom()
        .loadTrustMaterial((chain, authType) -> true)
        .build();
    SSLConnectionSocketFactory sslsf = new SSLConnectionSocketFactory(ssl, NoopHostnameVerifier.INSTANCE);
    PoolingHttpClientConnectionManager cm = PoolingHttpClientConnectionManagerBuilder.create()
        .setSSLSocketFactory(sslsf)
        .build();
    return HttpClients.custom().setConnectionManager(cm).build();
}

private static Connection login(CloseableHttpClient http, String url, String user, String password) throws Exception {
    Connection conn = new Connection(new JsonRpcClient(http, new URL(url + "/jsonrpc")));
    Session.loginWithPassword(conn, user, password, "1.0", "sdk-examples");
    return conn;
}
```

## Go

```go
func connect(url, user, password string) *xenapi.Session {
	session, err := login(url, user, password)
	if err == nil {
		return session
	}
	// A pool member names the coordinator's address; reconnect there (assuming the coordinator is up),
	// exactly as XenCenter does when you add a member server.
	coordinator := coordinatorFromSlaveError(err)
	if coordinator == "" {
		panic(err)
	}
	session, err = login("https://"+coordinator, user, password)
	if err != nil {
		panic(err)
	}
	return session
}

func login(url, user, password string) (*xenapi.Session, error) {
	session := xenapi.NewSession(&xenapi.ClientOpts{URL: url})
	_, err := session.LoginWithPassword(user, password, "1.0", "sdk-examples")
	return session, err
}

// coordinatorFromSlaveError returns the coordinator address carried by a HOST_IS_SLAVE error, or "".
// The Go binding surfaces API errors as a formatted string, rendering the error's data slice (the full
// XenAPI description, [code, ...params]) as "data [HOST_IS_SLAVE <addr>]" - so we recognise the code and
// take the address, which is the last element of that slice.
func coordinatorFromSlaveError(err error) string {
	msg := err.Error()
	if !strings.Contains(msg, xenapi.ErrorHostIsSlave) {
		return ""
	}
	if m := regexp.MustCompile(`data \[(.+)\]`).FindStringSubmatch(msg); m != nil {
		if fields := strings.Fields(m[1]); len(fields) > 0 {
			return fields[len(fields)-1]
		}
	}
	return ""
}
```

## PowerShell

```powershell
function Connect-Example {
    # A thin, reusable wrapper around the connect handshake described above, so each example can stay
    # focused on the task. Follows the pool-member -> coordinator redirect (HOST_IS_SLAVE).
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password
    )
    # Accepting the certificate in Connect-XenServer covers the module's cmdlets, and on Windows PowerShell
    # 5.1 Invoke-RestMethod/Invoke-WebRequest as well. PowerShell 7's web cmdlets keep their own trust, so
    # extend the same acceptance to them for the examples that talk to the host over plain HTTP(S).
    if ($PSVersionTable.PSVersion.Major -ge 6) {
        $global:PSDefaultParameterValues['Invoke-RestMethod:SkipCertificateCheck'] = $true
        $global:PSDefaultParameterValues['Invoke-WebRequest:SkipCertificateCheck'] = $true
    }
    try {
        return Connect-XenServer -Url $Url -UserName $UserName -Password $Password `
            -NoWarnCertificates -NoWarnNewCertificates -SetDefaultSession -PassThru
    }
    catch {
        # A pool member reports the coordinator's address in the HOST_IS_SLAVE error; reconnect there
        # (assuming the coordinator is up, as XenCenter does when you add a member server).
        $desc = $_.Exception.ErrorDescription
        if ($desc[0] -ne "HOST_IS_SLAVE") { throw }
        return Connect-XenServer -Url "https://$($desc[1])" -UserName $UserName -Password $Password `
            -NoWarnCertificates -NoWarnNewCertificates -SetDefaultSession -PassThru
    }
}
```

## xe CLI

```bash
# The one place the connection details live: every example just calls `xe <command> ...`.
xe() {
    # xe reports a failure on stdout. Captured by $(...), that text would land in the variable and set -e
    # would then stop the script without saying why, so pass a failure's output on to stderr instead.
    local out rc=0
    # `command`: when XE_EXE is unset, plain "xe" would be this function calling itself, without end.
    out=$(command "${XE_EXE:-xe}" -s "$host" "${xe_opts[@]}" -u "$user" -pw "$pass" "$@") || rc=$?
    if [ $rc -ne 0 ]; then [ -z "$out" ] || printf '%s\n' "$out" >&2; return $rc; fi
    [ -z "$out" ] || printf '%s\n' "$out"
}

# A pool member refuses every command with HOST_IS_SLAVE, naming the coordinator's address; send
# everything there instead (assuming the coordinator is up), as XenCenter does when you add a member server.
_probe=$(xe pool-list --minimal 2>&1) || true
if [[ $_probe =~ (Master|Coordinator)\ IP\ address:\ ([0-9A-Fa-f.:]+) ]]; then host=${BASH_REMATCH[2]}; fi
```
