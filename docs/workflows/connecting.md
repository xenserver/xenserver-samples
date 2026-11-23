<!-- Generated from workflows.json, the example sources and a run of each example. Edit those, not this file. -->

# Connecting

Every workflow starts the same way: open a session to the pool's coordinator, accepting its certificate (hosts ship with a self-signed one) and logging in. If you connect to a pool member instead, login fails with `HOST_IS_SLAVE` naming the coordinator, and these helpers reconnect there.

[All workflows](README.md)

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
        # (assuming the coordinator is up).
        $desc = $_.Exception.ErrorDescription
        if ($desc[0] -ne "HOST_IS_SLAVE") { throw }
        return Connect-XenServer -Url "https://$($desc[1])" -UserName $UserName -Password $Password `
            -NoWarnCertificates -NoWarnNewCertificates -SetDefaultSession -PassThru
    }
}
```

## xe CLI

```bash
# The one place the connection details live: every example calls `remote_xe <command> ...` - the xe client
# with this pool's address and credentials added - rather than xe itself, so none of them repeats them.
#
# This script's temporary files, removed however it ends. (workflows.sh runs the workflow in a subshell,
# so an EXIT trap a workflow sets for its own tidying up doesn't replace this one.)
_tmpfiles=()
trap 'rm -f "${_tmpfiles[@]}"' EXIT
# private_tempfile <variable>: a new temporary file, which mktemp makes readable by its owner only.
private_tempfile() { local f; f=$(mktemp); _tmpfiles+=("$f"); printf -v "$1" '%s' "$f"; }

# The password reaches xe in a file (-pwf), not on its command line, where other users could read it (ps)
# and logging tools could keep it. xe reads the user name from the file's first line and the password from
# its second. The Windows xe.exe has no -pwf, so it gets -u and -pw. The file is written before each call,
# so it always holds the current password (change-root-password changes it mid-run).
# xe_auth <password file> <user> <password>: sets _xe_auth to the options for that user and password.
xe_auth() {
    case "${XE_EXE:-xe}" in
        *.exe | *.EXE) _xe_auth=(-u "$2" -pw "$3") ;;
        *) printf '%s\n%s\n' "$2" "$3" > "$1"; _xe_auth=(-pwf "$1") ;;
    esac
}
private_tempfile _password_file

# xe reports a failure on stdout. Captured by $(...), that text would land in the variable and set -e
# would then stop the script without saying why, so pass a failure's output on to stderr instead, and
# return the real exit status - which workflows.sh's `set -euo pipefail` plus `inherit_errexit` then
# acts on: a plain `xe ...` or a `var=$(xe ...)` assignment stops the whole script. That does not reach
# a failure a `$(...)` only USES - an argument to echo/printf, a `[ ]` test, ... - because the shell
# never looks at that exit status at all; remote_xe_try is this same wrapper under its own name, for a
# call site that is deliberately checking whether xe succeeds (so the distinct name documents the intent,
# even though the function is identical).
remote_xe_try() {
    local out rc=0
    xe_auth "$_password_file" "$user" "$pass"
    out=$("${XE_EXE:-xe}" -s "$host" "${xe_opts[@]}" "${_xe_auth[@]}" "$@") || rc=$?
    if [ $rc -ne 0 ]; then [ -z "$out" ] || printf '%s\n' "$out" >&2; return $rc; fi
    [ -z "$out" ] || printf '%s\n' "$out"
}
# A `$(remote_xe ...)` used inside another command (an argument to echo, a `[ ]` test, ...) is beyond set
# -e's reach: the shell never looks at its exit status. So remote_xe also notes every failed call in a file
# - a variable would not survive the `$(...)` subshell - and ok() (helpers.sh) refuses to report success
# when any call failed, even one set -e could not see.
private_tempfile _xe_failures
remote_xe() { remote_xe_try "$@" || { local rc=$?; echo "xe $1 (exit $rc)" >> "$_xe_failures"; return $rc; }; }

# A pool member refuses every command with HOST_IS_SLAVE, naming the coordinator's address; send
# everything there instead (assuming the coordinator is up). Deliberately remote_xe_try: HOST_IS_SLAVE is
# reported as a failure, and is the expected outcome here as often as not.
_probe=$(remote_xe_try pool-list --minimal 2>&1) || true
if [[ $_probe =~ (Master|Coordinator)\ IP\ address:\ ([0-9A-Fa-f.:]+) ]]; then host=${BASH_REMATCH[2]}; fi
```

## Python

```python
def connect(url, username, password):
    """Open a session, skipping certificate validation for the host's self-signed cert.

    If url points at a pool *member* rather than the coordinator, login fails with HOST_IS_SLAVE
    naming the coordinator's address; we reconnect to it (assuming the coordinator is up)."""
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
        // is up).
        return Login($"https://{f.ErrorDescription[1]}", user, password);
    }
}

internal static Session Login(string url, string user, string password)
{
    var session = new Session(url);
    TrustHostCertificate(session);
    session.login_with_password(user, password, "1.0", "sdk-examples");
    return session;
}

/// <summary>Accept the host's self-signed certificate on a session's API calls.</summary>
internal static void TrustHostCertificate(Session session) =>
    session.JsonRpcClient.ServerCertificateValidationCallback = (_, _, _, _) => true;
```

## Go

```go
func connect(url, user, password string) *xenapi.Session {
	session, err := login(url, user, password)
	if err == nil {
		return session
	}
	// A pool member names the coordinator's address; reconnect there (assuming the coordinator is up).
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

## Java

```java
public static Connection connect(String url, String user, String password) throws Exception {
    CloseableHttpClient http = trustingHttpClient();
    try {
        return login(http, url, user, password);
    } catch (Types.HostIsSlave e) {
        // A pool member names the coordinator's address; reconnect there (assuming the coordinator
        // is up). Java SDKs up to 26.22 read that address as "" under JSON-RPC: say so rather than
        // connecting to "https://".
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
    // A synchronous call blocks until the operation finishes, and checkpointing, copying or exporting a
    // large VM can take many minutes: wait up to an hour for the answer rather than HttpClient's
    // three-minute default. (For anything longer, use the Async form and poll the task - see
    // WaitForTask.)
    PoolingHttpClientConnectionManager cm = PoolingHttpClientConnectionManagerBuilder.create()
        .setSSLSocketFactory(sslsf)
        .setDefaultConnectionConfig(ConnectionConfig.custom().setSocketTimeout(Timeout.ofHours(1)).build())
        .build();
    // Close a pooled connection once it has been idle for 30 seconds, so the next call opens a fresh one.
    // While a long HTTP transfer (a host backup, a disk export) runs, the API connection sits idle, and a
    // network that silently drops it meanwhile would leave the next call hanging until the socket
    // times out.
    return HttpClients.custom().setConnectionManager(cm).evictIdleConnections(TimeValue.ofSeconds(30)).build();
}

private static Connection login(CloseableHttpClient http, String url, String user, String password) throws Exception {
    Connection conn = new Connection(new JsonRpcClient(http, URI.create(url + "/jsonrpc").toURL()));
    Session.loginWithPassword(conn, user, password, "1.0", "sdk-examples");
    return conn;
}
```
