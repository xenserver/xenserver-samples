<!-- Generated from workflows.json, the example sources and a run of each example. Edit those, not this file. -->

# Back up a host's configuration

Download a host's configuration backup and check it is not empty; optionally stage it back onto that same host's backup partition, ready for a restore done from the installer.

**Caution:** with restore=true, overwrites the host's backup partition with the downloaded configuration.

Workflow `backup-host-config`. [All workflows](README.md) · [Connecting](connecting.md)

## PowerShell

Source: [`powershell/HostsAndPools/Invoke-BackupHostConfig.ps1`](../../powershell/HostsAndPools/Invoke-BackupHostConfig.ps1)

```powershell
function Invoke-BackupHostConfig {
    <#
    .SYNOPSIS
        Back up a host's configuration.
    .DESCRIPTION
        Download a host's configuration backup and verify it downloaded; optionally stage it back onto
        that same host's backup partition, ready for a restore done from the installer.
    .EXAMPLE
        Invoke-BackupHostConfig -Url https://xenserver -UserName root -Password $password
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password,
        [bool]$Restore = $false
    )
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password

    # The coordinator: always reachable at the pool's address. (Back up every host, in practice.)
    $vmHost = Get-XenHost -Ref (Get-XenPool).master
    $hostUrl = Get-HostUrl -Url $Url -Address $vmHost.address
    Write-Host "Backing up $($vmHost.name_label)"

    # Both halves are served only by whichever host physically accepted the HTTP connection - the
    # handler ignores any ref= in the query string entirely, there is no forwarding to another pool
    # member. So backing up/restoring a host means opening the connection to THAT host's own address,
    # not to the pool's (coordinator) URL. ref= is kept in the query string purely for log-readability
    # (a real host ignores it). Still pure PowerShell: Connect-Example has already trusted the server's
    # certificate.
    #
    # -OutFile/-InFile below already stream straight to/from disk rather than buffering the whole file,
    # and there is no idle-connection step to take after the transfer (unlike the Python/Java ports):
    # this module's cmdlets dispatch through the C# binding's Session/JsonRpcClient, whose
    # PerformPostRequest opens a brand-new HttpClient per XenAPI call and disposes it immediately
    # afterwards - there is no kept-alive session connection that a long transfer could leave idle.
    $path = Join-Path ([IO.Path]::GetTempPath()) "sdk-example-host-$([guid]::NewGuid().Guid).backup"
    Invoke-WebRequest -UseBasicParsing -OutFile $path -TimeoutSec 10 `
        -Uri "$hostUrl/host_backup?session_id=$($session.opaque_ref)&ref=$($vmHost.opaque_ref)"
    $size = (Get-Item $path).Length
    if ($size -eq 0) { throw "$path came back empty" }
    Write-Host "  wrote $size bytes to $(Split-Path $path -Leaf)"

    if ($Restore) {
        # host-restore does not restore the host there and then: it only writes the archive over that
        # host's currently inactive backup partition, ready for the next boot. It takes effect only once
        # that host is booted from the installer and Restore is chosen there.
        Restore-ExampleHostConfig -Session $session -HostUrl $hostUrl -VMHost $vmHost -Path $path
        Write-Host ("  staged it on $($vmHost.name_label)'s backup partition - it takes effect only after " +
            "booting that host from the installer and choosing Restore")
    }
    else {
        Write-Host "  not restoring it (pass -Restore `$true to stage it on $($vmHost.name_label)'s backup partition)"
    }

    Remove-Item $path
    Write-Host "OK: backup-host-config"
    $session | Disconnect-XenServer
}

function Get-HostUrl {
    <#
    .SYNOPSIS
        Build the URL for a given host's own address, keeping the scheme and port the caller originally
        connected with (a host's management address carries no port of its own).
    #>
    param([string]$Url, [string]$Address)
    $uri = [System.Uri]$Url
    $port = if ($uri.Port -gt 0) { ":$($uri.Port)" } else { "" }
    return "$($uri.Scheme)://$Address$port"
}

function Restore-ExampleHostConfig {
    <#
    .SYNOPSIS
        Uploads a backup to a host - over a connection opened to THAT host's own address - and raises if
        the task reports it was refused.
    .DESCRIPTION
        An upload answers 200 as soon as it has read the request headers, because the client waits for that
        before it starts sending the file. The outcome therefore cannot be in the status line: it arrives on
        a task you create first, name in the URL, and poll once the upload has finished.
    #>
    param($Session, [string]$HostUrl, $VMHost, [string]$Path)

    $task = New-XenTask -Label 'host_restore' -Description 'restoring a configuration backup' -PassThru
    try {
        # The timeout covers the whole transfer: a backup is hundreds of MB, so allow for a slow network.
        Invoke-WebRequest -UseBasicParsing -Method Put -InFile $Path -TimeoutSec 1800 `
            -Uri ("$HostUrl/host_restore?session_id=$($Session.opaque_ref)" +
                  "&ref=$($VMHost.opaque_ref)&task_id=$($task.opaque_ref)") | Out-Null

        while ((Get-XenTask -Ref $task).status -eq 'pending') { Start-Sleep -Milliseconds 500 }
        $finished = Get-XenTask -Ref $task
        if ($finished.status -ne 'success') {
            throw "refused ($($finished.error_info[-1]))"
        }
    }
    finally {
        Remove-XenTask -Ref $task
    }
}
```

<details><summary>Example output</summary>

```text
Backing up sdk-host1
  wrote 83 bytes to sdk-example-host-39843df2-0e33-43ed-82b8-fe8c12adf9c2.backup
  not restoring it (pass -Restore $true to stage it on sdk-host1's backup partition)
OK: backup-host-config
```

</details>

## xe CLI

Source: [`cli/hosts-and-pools/backup-host-config.sh`](../../cli/hosts-and-pools/backup-host-config.sh)

```bash
# Back up a host's configuration.
#
# Download a host's configuration backup and verify it downloaded. With restore=true, stage it back onto
# the same host's backup partition: host-restore does not restore the host there and then, it only writes
# the archive over that host's (currently inactive) backup partition, ready for the next boot.
#
# Run it:
#   ./workflows.sh backup-host-config https://xenserver root "$password"
#
# Optional key=value arguments (default):
#   restore (false)

backup_host_config() {
    local restore
    restore=$(param restore false)
    # Deliberately not `host`: that is the variable the xe() helper dials, and shadowing it here sent
    # every later command to a server named after the host's UUID.
    # The coordinator: always reachable at the pool's address. (Back up every host, in practice.)
    target=$(xe pool-param-get uuid=$(xe pool-list --minimal) param-name=master)
    echo "Backing up $(xe host-param-get uuid=$target param-name=name-label)"

    # Relative to the working directory: xe.exe and this script must agree on the path, and a Windows
    # temp directory spelled with backslashes would not survive the trip through both.
    file="cli-host.backup"
    rm -f "$file"   # xe refuses to overwrite an existing file rather than clobbering it
    # xe does the HTTP transfer itself: the server answers the command by telling the client to GET
    # /host_backup, and xe writes the file. Nothing streams down the CLI connection.
    xe host-backup uuid=$target file-name="$file"
    size=$(stat -c %s "$file" 2>/dev/null || wc -c < "$file")
    [ "$size" -gt 0 ] || { echo "backup-host-config: $file came back empty" >&2; exit 1; }
    echo "  wrote $size bytes to $file"

    if [ "$restore" = true ]; then
        # host-restore writes the archive over the host's own backup partition - the inactive one, never
        # the partition it is currently running from. It only takes effect once you boot that host from
        # the installer and choose Restore there.
        xe host-restore uuid=$target file-name="$file"
        echo "  staged it on $(xe host-param-get uuid=$target param-name=name-label)'s backup partition" \
             "- it takes effect only after booting that host from the installer and choosing Restore"
    else
        echo "  not restoring it (pass restore=true to stage it on $(xe host-param-get uuid=$target param-name=name-label)'s backup partition)"
    fi

    rm -f "$file"
    ok backup-host-config
}
```

<details><summary>Example output</summary>

```text
Backing up sdk-host1
  wrote 83 bytes to cli-host.backup
  not restoring it (pass restore=true to stage it on sdk-host1's backup partition)
OK: backup-host-config
```

</details>

## Python

Source: [`python/hosts_and_pools/backup_host_config.py`](../../python/hosts_and_pools/backup_host_config.py)

```python
"""Back up a host's configuration.

Download a host's configuration backup and verify it downloaded; optionally stage it back onto that
same host's backup partition, ready for a restore done from the installer.
"""

import os
import shutil
import ssl
import tempfile
import time
import urllib.parse
import urllib.request

from connection import connect


def backup_host_config(url, username, password, restore=False):
    """Download a host's configuration backup and verify it, then optionally stage it back as a restore.

    Both halves are HTTP transfers alongside the API rather than API calls, and the upload
    has a convention worth knowing: the server answers 200 as soon as it has read the
    request headers, because the client waits for that before it starts sending the file.
    The outcome therefore cannot be in the status line. It arrives on a task you create
    first, name in the URL, and poll once the upload has finished.

    Both halves are served only by whichever host physically accepted the HTTP connection - the
    handler ignores any ref= in the query string entirely, there is no forwarding to another pool
    member. So backing up/restoring a host means opening the connection to THAT host's own
    address, not to the pool's (coordinator) url. ref= is kept in the query string purely for
    log-readability (a real host ignores it).

    restore=True stages the backup onto the SAME host's backup partition (restore=true from the
    command line, or the Python bool). host-restore does not restore the host there and then: it only
    writes the archive over that host's currently inactive backup partition, ready for the next boot.
    It takes effect only once that host is booted from the installer and Restore is chosen there."""
    if isinstance(restore, str):  # from the command line
        restore = restore.lower() == "true"
    session = connect(url, username, password)
    x = session.xenapi
    ctx = ssl._create_unverified_context()

    # The coordinator: always reachable at the pool's address. (Back up every host, in practice.)
    host = x.pool.get_master(x.pool.get_all()[0])
    host_url = _host_url(url, x.host.get_address(host))
    print("Backing up %s" % x.host.get_name_label(host))

    path = os.path.join(tempfile.gettempdir(), "sdk-example-host.backup")
    with urllib.request.urlopen(
            "%s/host_backup?session_id=%s&ref=%s" % (host_url, session._session, host),
            context=ctx, timeout=1800) as response, open(path, "wb") as out:   # the host packs it first
        shutil.copyfileobj(response, out)       # hundreds of MB: stream it, don't hold it in memory
    size = os.path.getsize(path)
    if size == 0:
        raise RuntimeError("%s came back empty" % path)
    print("  wrote %d bytes to %s" % (size, os.path.basename(path)))
    _drop_idle_connection(session)

    name = x.host.get_name_label(host)
    if restore:
        restore_host_config(session, ctx, host_url, host, path)
        print("  staged it on %s's backup partition - it takes effect only after booting that host "
              "from the installer and choosing Restore" % name)
    else:
        print("  not restoring it (pass restore=true to stage it on %s's backup partition)" % name)

    os.remove(path)
    print("OK: backup-host-config")
    session.logout()


def _host_url(url, address):
    """Build the URL for a given host's own address, keeping the scheme and port the caller
    originally connected with (a host's management address carries no port of its own)."""
    parts = urllib.parse.urlsplit(url)
    port = ":%d" % parts.port if parts.port else ""
    return "%s://%s%s" % (parts.scheme, address, port)


def _drop_idle_connection(session):
    """Close the session's HTTP connection after a long transfer; the next call opens a new one.
    The session itself is still valid - but its one keep-alive connection sat idle for as long as
    the transfer took, and a network that dropped it meanwhile leaves the next call hanging until
    the socket times out. (ServerProxy("close")() is xmlrpc.client's way to close its transport.)"""
    session("close")()


def restore_host_config(session, ctx, host_url, host, path):
    """Upload a backup to a host - over a connection opened to THAT host's own address - and raise
    if the task reports it was refused."""
    x = session.xenapi
    task = x.task.create("host_restore", "restoring a configuration backup")
    try:
        with open(path, "rb") as f:
            request = urllib.request.Request(
                "%s/host_restore?session_id=%s&ref=%s&task_id=%s" % (host_url, session._session, host, task),
                data=f, headers={"Content-Length": str(os.path.getsize(path))}, method="PUT")
            # The timeout covers each socket operation, including waiting for the host's answer once the
            # whole backup (hundreds of MB) has arrived - a real host takes far longer than seconds.
            urllib.request.urlopen(request, context=ctx, timeout=1800).read()
        _drop_idle_connection(session)

        while x.task.get_status(task) == "pending":
            time.sleep(0.5)
        if x.task.get_status(task) != "success":
            raise RuntimeError("refused (%s)" % x.task.get_error_info(task)[-1])
    finally:
        x.task.destroy(task)
```

<details><summary>Example output</summary>

```text
Backing up sdk-host1
  wrote 83 bytes to sdk-example-host.backup
  not restoring it (pass restore=true to stage it on sdk-host1's backup partition)
OK: backup-host-config
```

</details>

## C# (.NET)

Source: [`csharp/HostsAndPools/BackupHostConfig.cs`](../../csharp/HostsAndPools/BackupHostConfig.cs)

```csharp
/// <summary>
/// Download a host's configuration backup and verify it downloaded; optionally stage it back onto that
/// same host's backup partition, ready for a restore done from the installer.
/// </summary>
/// <example>
/// <code>
/// Workflows.BackupHostConfig("https://xenserver", "root", password);
/// </code>
/// </example>
/// <remarks>
/// Both /host_backup and /host_restore are served only by whichever host physically accepted the HTTP
/// connection - the handler is keyed off the connection's own address, not any ref= in the query string.
/// So backing up/restoring a host means opening the connection to THAT host's own address, not the pool's
/// (coordinator) url. ref= is kept in the query string for readability in the host's logs.
/// </remarks>
public static void BackupHostConfig(string url, string user, string password, bool restore = false)
{
    var session = Connect(url, user, password);

    // The coordinator: always reachable at the pool's address. (Back up every host, in practice.)
    var host = Pool.get_master(session, Pool.get_all(session)[0]);
    var hostUrl = HostUrl(url, Host.get_address(session, host));
    Console.WriteLine($"Backing up {Host.get_name_label(session, host)}");

    // Stream it: a real host's backup can be hundreds of MB, too large to hold in memory (and,
    // unlike Python's binding, each XenAPI call below opens its own fresh HttpClient - see
    // RestoreHostConfig - so there's no idle keep-alive connection here that needs dropping first).
    var path = Path.Combine(Path.GetTempPath(), $"sdk-example-host-{Guid.NewGuid():N}.backup");
    using (var client = InsecureHttpClient())
    {
        using var response = client.GetAsync(
            $"{hostUrl}/host_backup?session_id={session.opaque_ref}&ref={host.opaque_ref}",
            HttpCompletionOption.ResponseHeadersRead).Result;
        response.EnsureSuccessStatusCode();
        using (var httpStream = response.Content.ReadAsStreamAsync().Result)
        using (var fileStream = File.Create(path))
            httpStream.CopyTo(fileStream);
    }
    var size = new FileInfo(path).Length;
    if (size == 0) throw new InvalidOperationException($"{path} came back empty");
    Console.WriteLine($"  wrote {size} bytes to {Path.GetFileName(path)}");

    var name = Host.get_name_label(session, host);
    if (restore)
    {
        // host-restore does not restore the host there and then: it only writes the archive over that
        // host's currently inactive backup partition, ready for the next boot. It takes effect only
        // once that host is booted from the installer and Restore is chosen there.
        RestoreHostConfig(session, hostUrl, host, path);
        Console.WriteLine($"  staged it on {name}'s backup partition - it takes effect only after "
                          + "booting that host from the installer and choosing Restore");
    }
    else
    {
        Console.WriteLine($"  not restoring it (pass restore=true to stage it on {name}'s backup partition)");
    }

    File.Delete(path);
    Console.WriteLine("OK: backup-host-config");
    session.logout();
}

/// <summary>
/// Build the URL for a given host's own address, keeping the scheme and port the caller originally
/// connected with (a host's management address carries no port of its own).
/// </summary>
private static string HostUrl(string url, string address)
{
    var uri = new Uri(url);
    var port = uri.IsDefaultPort ? "" : $":{uri.Port}";
    return $"{uri.Scheme}://{address}{port}";
}

/// <summary>
/// Upload a backup to a host - over a connection opened to THAT host's own address - and throw if
/// the task reports it was refused.
/// </summary>
/// <remarks>
/// An upload answers 200 as soon as it has read the request headers, because the client waits for that
/// before it starts sending the file. The outcome therefore cannot be in the status line: it arrives on
/// a task you create first, name in the URL, and poll once the upload has finished.
/// </remarks>
private static void RestoreHostConfig(Session session, string hostUrl, XenRef<Host> host, string path)
{
    var task = Task.create(session, "host_restore", "restoring a configuration backup").opaque_ref;
    try
    {
        // Stream the upload too, rather than reading the whole backup into memory first. Every
        // XenAPI call this binding makes (including task.create/get_status below) opens a brand new
        // HttpClient and tears it down again - unlike Python's single long-lived xmlrpc.client
        // connection, there is no idle keep-alive connection here left over from the transfer that
        // would need to be dropped before the next call.
        using (var client = InsecureHttpClient())
        using (var fileStream = File.OpenRead(path))
        {
            var response = client.PutAsync(
                $"{hostUrl}/host_restore?session_id={session.opaque_ref}&ref={host.opaque_ref}&task_id={task}",
                new StreamContent(fileStream)).Result;
            response.EnsureSuccessStatusCode();
        }

        while (Task.get_status(session, task) == task_status_type.pending)
            System.Threading.Thread.Sleep(500);
        if (Task.get_status(session, task) != task_status_type.success)
            throw new InvalidOperationException($"refused ({Task.get_error_info(session, task).Last()})");
    }
    finally
    {
        Task.destroy(session, task);
    }
}
```

<details><summary>Example output</summary>

```text
Backing up sdk-host1
  wrote 83 bytes to sdk-example-host-0fde92ec17e542f9acb09791fd5ba469.backup
  not restoring it (pass restore=true to stage it on sdk-host1's backup partition)
OK: backup-host-config
```

</details>

## Go

Source: [`go/backup_host_config.go`](../../go/backup_host_config.go)

```go
package main

import (
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"time"

	"go/xenapi"
)

// backupHostConfig - Back up a host's configuration.
//
// Download a host's configuration backup and verify it downloaded; optionally stage it back onto that
// same host's backup partition, ready for a restore done from the installer.
//
// Both /host_backup and /host_restore are served only by whichever host physically accepted the
// HTTP connection - the handler ignores any ref= in the query string entirely, there is no
// forwarding to another pool member. So backing up/restoring a host means opening the connection
// to THAT host's own address, not to the pool's (coordinator) url. ref= is kept in the query string
// purely for log-readability (a real host ignores it).
//
// Both halves are hundreds of MB on a real host, so they stream to/from a temp file rather than
// holding the backup in memory. A transfer takes long enough on a slow link for the network to drop
// an API connection left idle meanwhile, and the next call would then hang on it until the socket
// timed out - so this session sends "Connection: close", giving every API call its own connection.
//
// restore stages the backup onto the SAME host's backup partition. host-restore does not restore the
// host there and then: it only writes the archive over that host's currently inactive backup
// partition, ready for the next boot. It takes effect only once that host is booted from the
// installer and Restore is chosen there.
func backupHostConfig(url, user, password string, restore bool) {
	session := xenapi.NewSession(&xenapi.ClientOpts{URL: url, Headers: map[string]string{"Connection": "close"}})
	_, err := session.LoginWithPassword(user, password, "1.0", "sdk-examples")
	check(err)
	defer session.Logout()

	// The coordinator: always reachable at the pool's address. (Back up every host, in practice.)
	pools, err := xenapi.Pool.GetAll(session)
	check(err)
	host, err := xenapi.Pool.GetMaster(session, pools[0])
	check(err)
	name, err := xenapi.Host.GetNameLabel(session, host)
	check(err)
	address, err := xenapi.Host.GetAddress(session, host)
	check(err)
	hostAddr := hostURL(url, address)
	fmt.Printf("Backing up %s\n", name)

	// Backup and restore are HTTP transfers alongside the API, not API calls, so the session id travels
	// in the query string. The Go binding keeps its own session private, so obtain one of our own.
	sid := rawLogin(url, user, password)
	temp, err := os.CreateTemp("", "sdk-example-host-*.backup")
	check(err)
	path := temp.Name()

	resp, err := insecureClient().Get(
		fmt.Sprintf("%s/host_backup?session_id=%s&ref=%s", hostAddr, sid, host))
	check(err)
	// Hundreds of MB on a real host: stream it to disk, don't hold it in memory.
	_, err = io.Copy(temp, resp.Body)
	check(err)
	resp.Body.Close()
	check(temp.Close())
	info, err := os.Stat(path)
	check(err)
	if info.Size() == 0 {
		panic(fmt.Sprintf("%s came back empty", path))
	}
	fmt.Printf("  wrote %d bytes to %s\n", info.Size(), filepath.Base(path))

	if restore {
		restoreHostConfig(session, hostAddr, sid, host, path)
		fmt.Printf("  staged it on %s's backup partition - it takes effect only after booting that host "+
			"from the installer and choosing Restore\n", name)
	} else {
		fmt.Printf("  not restoring it (pass restore=true to stage it on %s's backup partition)\n", name)
	}

	check(os.Remove(path))
	fmt.Println("OK: backup-host-config")
}

// hostURL rebuilds a URL for a different host's own address, keeping the original scheme and port
// (a host's management "address" field carries no port of its own). Needed anywhere a workflow
// does raw HTTP against a SPECIFIC host rather than the pool's connection URL.
func hostURL(rawURL, address string) string {
	u, err := url.Parse(rawURL)
	check(err)
	host := address
	if port := u.Port(); port != "" {
		host = address + ":" + port
	}
	return u.Scheme + "://" + host
}

// restoreHostConfig uploads a backup to a host - over a connection opened to THAT host's own
// address - and panics if the task reports it was refused.
//
// An upload answers 200 as soon as it has read the request headers, because the client waits for that
// before it starts sending the file. The outcome therefore cannot be in the status line: it arrives on a
// task you create first, name in the URL, and poll once the upload has finished.
func restoreHostConfig(session *xenapi.Session, url, sid string, host xenapi.HostRef, path string) {
	task, err := xenapi.Task.Create(session, "host_restore", "restoring a configuration backup")
	check(err)
	defer xenapi.Task.Destroy(session, task)

	file, err := os.Open(path)
	check(err)
	defer file.Close()
	info, err := os.Stat(path)
	check(err)

	// Stream the file as the request body rather than reading it into memory first: a real host's
	// backup is hundreds of MB. http.NewRequest can't infer the length of an arbitrary io.Reader, so
	// set ContentLength explicitly - without it Go would send chunked Transfer-Encoding, which isn't
	// what a real host's /host_restore handler expects.
	request, err := http.NewRequest(http.MethodPut,
		fmt.Sprintf("%s/host_restore?session_id=%s&ref=%s&task_id=%s", url, sid, host, task),
		file)
	check(err)
	request.ContentLength = info.Size()
	resp, err := insecureClient().Do(request)
	check(err)
	io.Copy(io.Discard, resp.Body)
	resp.Body.Close()

	for {
		status, err := xenapi.Task.GetStatus(session, task)
		check(err)
		if status != xenapi.TaskStatusTypePending {
			if status == xenapi.TaskStatusTypeSuccess {
				return
			}
			info, err := xenapi.Task.GetErrorInfo(session, task)
			check(err)
			panic(fmt.Sprintf("refused (%s)", info[len(info)-1]))
		}
		time.Sleep(500 * time.Millisecond)
	}
}
```

<details><summary>Example output</summary>

```text
Backing up sdk-host1
  wrote 83 bytes to sdk-example-host-3435847481.backup
  not restoring it (pass restore=true to stage it on sdk-host1's backup partition)
OK: backup-host-config
```

</details>

## Java

Source: [`java/src/main/java/com/xenserver/samples/hostsandpools/BackupHostConfig.java`](../../java/src/main/java/com/xenserver/samples/hostsandpools/BackupHostConfig.java)

```java
package com.xenserver.samples.hostsandpools;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.Host;
import com.xensource.xenapi.JsonRpcClient;
import com.xensource.xenapi.Session;
import com.xensource.xenapi.Task;
import com.xensource.xenapi.Types;

import org.apache.hc.client5.http.classic.methods.HttpGet;
import org.apache.hc.client5.http.classic.methods.HttpPut;
import org.apache.hc.client5.http.impl.classic.CloseableHttpClient;
import org.apache.hc.core5.http.io.entity.EntityUtils;

import java.net.URL;

import static com.xenserver.samples.Helpers.hostUrl;
import static com.xenserver.samples.PoolConnection.connect;
import static com.xenserver.samples.PoolConnection.trustingHttpClient;

public final class BackupHostConfig {
    private BackupHostConfig() {
    }

    /**
     * Back up a host's configuration.
     *
     * <p>Download a host's configuration backup and verify it downloaded; optionally stage it back onto
     * that same host's backup partition, ready for a restore done from the installer.
     *
     * <p>Both /host_backup and /host_restore are served only by whichever host physically accepted the
     * HTTP connection - the handler ignores any ref= in the query string entirely, there is no forwarding
     * to another pool member. So backing up/restoring a host means opening the connection to THAT host's
     * own address, not to the pool's (coordinator) url. ref= is kept in the query string purely for
     * log-readability (a real host ignores it).
     *
     * <p>restore=true stages the backup onto the SAME host's backup partition. host-restore does not
     * restore the host there and then: it only writes the archive over that host's currently inactive
     * backup partition, ready for the next boot. It takes effect only once that host is booted from the
     * installer and Restore is chosen there.
     *
     * <p>Run it:
     *
     * <pre>{@code
     * BackupHostConfig.run("https://xenserver", "root", password, false);
     * }</pre>
     */
    public static void run(String url, String user, String password, boolean restore) throws Exception {
        Connection conn = connect(url, user, password);
        try {
            // The coordinator: always reachable at the pool's address. (Back up every host, in practice.)
            Host host = com.xensource.xenapi.Pool.getAll(conn).iterator().next().getMaster(conn);
            String session = conn.getSessionReference();
            String hostUrl = hostUrl(url, host.getAddress(conn));
            System.out.println("Backing up " + host.getNameLabel(conn));

            // Backup and restore are HTTP transfers alongside the API, not API calls, so the session id
            // travels in the query string.
            java.io.File file = java.io.File.createTempFile("sdk-example-host", ".backup");
            HttpGet get = new HttpGet(hostUrl + "/host_backup?session_id=" + session
                    + "&ref=" + host.toWireString());
            // Hundreds of MB: stream it to disk rather than holding the whole backup in memory.
            try (CloseableHttpClient http = trustingHttpClient()) {
                http.execute(get, resp -> {
                    try (java.io.InputStream in = resp.getEntity().getContent()) {
                        java.nio.file.Files.copy(in, file.toPath(),
                                java.nio.file.StandardCopyOption.REPLACE_EXISTING);
                    }
                    return null;
                });
            }
            if (file.length() == 0) throw new IllegalStateException(file + " came back empty");
            System.out.printf("  wrote %d bytes to %s%n", file.length(), file.getName());
            // The connection's one keep-alive HTTP connection sat idle for as long as the download
            // took; a network that silently dropped it meanwhile would otherwise leave the next call
            // (Task.create below) hanging until the socket times out, so get a fresh one for the same
            // session before making another API call.
            conn = dropIdleConnection(conn, url);

            String name = host.getNameLabel(conn);
            if (restore) {
                conn = restoreHostConfig(conn, url, hostUrl, session, host, file);
                System.out.println("  staged it on " + name + "'s backup partition - it takes effect only "
                        + "after booting that host from the installer and choosing Restore");
            } else {
                System.out.println("  not restoring it (pass restore=true to stage it on "
                        + name + "'s backup partition)");
            }

            file.delete();
            System.out.println("OK: backup-host-config");
        } finally {
            Session.logout(conn);
        }
    }

    /**
     * Close the connection's HTTP connection pool after a long transfer, so the next XenAPI call opens a
     * fresh one - the previous JsonRpcClient's one keep-alive connection sat idle for as long as the
     * transfer took, and a network that dropped it meanwhile leaves the next call hanging until the socket
     * times out. Connection has no public way to discard its pooled connections or to attach a custom
     * JsonRpcClient to an existing session at the same time, so build a fresh Connection (still trusting
     * the host's certificate, like connect() does) and set its session reference directly - there is no
     * public setter for that field.
     */
    private static Connection dropIdleConnection(Connection conn, String url) throws Exception {
        Connection fresh = new Connection(new JsonRpcClient(trustingHttpClient(), new URL(url + "/jsonrpc")));
        java.lang.reflect.Field sessionField = Connection.class.getDeclaredField("sessionReference");
        sessionField.setAccessible(true);
        sessionField.set(fresh, conn.getSessionReference());
        return fresh;
    }

    /**
     * Uploads a backup to a host - over a connection opened to THAT host's own address - and throws if
     * the task reports it was refused. Returns the (possibly renewed) connection to continue with.
     *
     * <p>An upload answers 200 as soon as it has read the request headers, because the client waits for
     * that before it starts sending the file. The outcome therefore cannot be in the status line: it
     * arrives on a task you create first, name in the URL, and poll once the upload has finished.
     */
    private static Connection restoreHostConfig(Connection conn, String apiUrl,
            String hostUrl, String session, Host host, java.io.File file) throws Exception {
        Task task = Task.create(conn, "host_restore", "restoring a configuration backup");
        try {
            HttpPut put = new HttpPut(hostUrl + "/host_restore?session_id=" + session
                    + "&ref=" + host.toWireString() + "&task_id=" + task.toWireString());
            // Stream the file rather than reading it into memory first; the entity reports the file's
            // own length as the Content-Length the server needs up front.
            put.setEntity(new org.apache.hc.core5.http.io.entity.FileEntity(
                    file, org.apache.hc.core5.http.ContentType.APPLICATION_OCTET_STREAM));
            try (CloseableHttpClient http = trustingHttpClient()) {
                http.execute(put, resp -> EntityUtils.toString(resp.getEntity()));
            }
            // As above: the connection sat idle for as long as the upload took. Reconnect to the
            // coordinator: the upload went to the host itself, but a pool member refuses API calls.
            conn = dropIdleConnection(conn, apiUrl);

            while (task.getStatus(conn) == Types.TaskStatusType.PENDING) Thread.sleep(500);
            if (task.getStatus(conn) != Types.TaskStatusType.SUCCESS) {
                // error_info is declared as a SET of strings, and the Java binding hands back a real
                // Set - so there is no "last element" to read the detail from. Print it whole rather
                // than indexing into something unordered; see the WLB example, where guessing at an
                // order silently lied.
                throw new IllegalStateException("refused " + task.getErrorInfo(conn));
            }
            return conn;
        } finally {
            task.destroy(conn);
        }
    }
}
```

<details><summary>Example output</summary>

```text
Backing up sdk-host1
  wrote 83 bytes to sdk-example-host13201454403948149848.backup
  not restoring it (pass restore=true to stage it on sdk-host1's backup partition)
OK: backup-host-config
```

</details>
