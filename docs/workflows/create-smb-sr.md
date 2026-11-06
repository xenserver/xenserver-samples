<!-- Generated from workflows.json, the example sources and a run of each example. Edit those, not this file. -->

# Create an SMB SR

Connect a shared storage repository to an SMB/CIFS file share, passing the server, share path and credentials (the password as a secret, never in plain text).

**Requires:** an SMB file share.

Workflow `create-smb-sr`. [All workflows](README.md) · [Connecting](connecting.md)

## PowerShell

Source: [`powershell/Storage/Invoke-CreateSmbSr.ps1`](../../powershell/Storage/Invoke-CreateSmbSr.ps1)

```powershell
function Invoke-CreateSmbSr {
    <#
    .SYNOPSIS
        Create an SMB SR.
    .DESCRIPTION
        Connect a shared storage repository to an SMB/CIFS file share, passing the server, share path and
        credentials (the password as a secret, never in plain text).
    .EXAMPLE
        Invoke-CreateSmbSr -Url https://xenserver -UserName root -Password $password
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password,
        [Parameter(Mandatory = $true)][string]$Server,
        [Parameter(Mandatory = $true)][string]$Share,
        [Parameter(Mandatory = $true)][string]$SmbUsername,
        [Parameter(Mandatory = $true)][string]$SmbPassword,
        [string]$SrName = "sdk-example-smb"
    )
    # Connect a shared SR to an SMB/CIFS file share (create validates + sizes from the share).
    #
    # The password travels as a Secret, not plaintext device-config.
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password
    $xenHost = Get-XenHost | Select-Object -First 1

    $secret = New-XenSecret -Value $SmbPassword -OtherConfig @{} -PassThru
    $deviceConfig = @{
        # server is the share as one UNC path, //server/share: the SMB driver has no separate serverpath.
        server          = "//$Server$Share"
        username        = $SmbUsername
        password_secret = $secret.uuid
    }
    $sr = New-XenSR -XenHost $xenHost -DeviceConfig $deviceConfig -PhysicalSize 0 `
        -NameLabel $SrName -NameDescription "SMB SR created by the SDK example" `
        -Type "smb" -ContentType "user" -Shared $true -PassThru
    Write-Host "Created SR: $($sr.uuid) ($([math]::Floor([long]($sr.physical_size) / 1GB)) GiB)"
    Invoke-DetachAndForgetSr -Ref $sr
    Remove-XenSecret -Ref $secret
    Write-Host "OK: create-smb-sr"
    $session | Disconnect-XenServer
}
```

<details><summary>Example output</summary>

```text
Created SR: 00000001-0000-0000-df0a-000000000000 (512 GiB)
OK: create-smb-sr
```

</details>

## xe CLI

Source: [`cli/storage/create-smb-sr.sh`](../../cli/storage/create-smb-sr.sh)

```bash
# Create an SMB SR.
#
# Connect a shared storage repository to an SMB/CIFS file share, passing the server, share path and
# credentials (the password as a secret, never in plain text).
#
# Run it:
#   ./workflows.sh create-smb-sr https://xenserver root "$password"
#
# Optional key=value arguments (default):
#   server (192.0.2.40)
#   share (/vmstore)
#   smb_username (Administrator)
#   smb_password (Password1)
#   sr_name (xe-example-smb)

create_smb_sr() {
    local server share smb_username smb_password sr_name secret sr
    server=$(param server "192.0.2.40")
    share=$(param share "/vmstore")
    smb_username=$(param smb_username "Administrator")
    smb_password=$(param smb_password "Password1")
    sr_name=$(param sr_name "xe-example-smb")

    # The password travels as a Secret, not plaintext device-config.
    secret=$(xe secret-create value="$smb_password")
    sr=$(xe sr-create host-uuid=$(first_host) type=smb name-label="$sr_name" shared=true \
        device-config:server="//$server$share" \
        device-config:username="$smb_username" device-config:password_secret=$secret)
    echo "Created SMB SR: $sr ($(( $(xe sr-param-get uuid=$sr param-name=physical-size) / 1024 / 1024 / 1024 )) GiB)"
    detach_and_forget_sr $sr
    xe secret-destroy uuid=$secret
    echo "OK: create-smb-sr"
}
```

<details><summary>Example output</summary>

```text
Created SMB SR: 00000001-0000-0000-be0a-000000000000 (512 GiB)
OK: create-smb-sr
```

</details>

## Python

Source: [`python/storage/create_smb_sr.py`](../../python/storage/create_smb_sr.py)

```python
"""Create an SMB SR.

Connect a shared storage repository to an SMB/CIFS file share, passing the server, share path and
credentials (the password as a secret, never in plain text).
"""

from connection import connect
from helpers import detach_and_forget_sr


def create_smb_sr(url, username, password, server, share, smb_username, smb_password,
                   sr_name="sdk-example-smb"):
    """Connect a shared SR to an SMB/CIFS file share (create validates + sizes from the share).

    The password travels as a Secret, not plaintext device-config."""
    GIB = 1024 * 1024 * 1024
    session = connect(url, username, password)
    host = session.xenapi.host.get_all()[0]

    secret = session.xenapi.secret.create({"value": smb_password, "other_config": {}})
    # server is the share as one UNC path, //server/share: the SMB driver has no separate serverpath.
    dc = {"server": "//%s%s" % (server, share), "username": smb_username,
          "password_secret": session.xenapi.secret.get_uuid(secret)}
    sr = session.xenapi.SR.create(host, dc, "0", sr_name,
                                  "SMB SR created by the SDK example", "smb", "user", True, {})
    print("Created SR: %s (%d GiB)"
          % (session.xenapi.SR.get_uuid(sr), int(session.xenapi.SR.get_physical_size(sr)) // GIB))
    detach_and_forget_sr(session, sr)
    session.xenapi.secret.destroy(secret)
    print("OK: create-smb-sr")
    session.logout()
```

<details><summary>Example output</summary>

```text
Created SR: 00000001-0000-0000-0c0b-000000000000 (512 GiB)
OK: create-smb-sr
```

</details>

## C# (.NET)

Source: [`csharp/Storage/CreateSmbSr.cs`](../../csharp/Storage/CreateSmbSr.cs)

```csharp
/// <summary>
/// Connect a shared storage repository to an SMB/CIFS file share, passing the server, share path and
/// credentials (the password as a secret, never in plain text).
/// </summary>
/// <example>
/// <code>
/// Workflows.CreateSmbSr("https://xenserver", "root", password, "192.0.2.40", "/vmstore", "Administrator", "Password1");
/// </code>
/// </example>
/// <remarks>
/// Connect a shared SR to an SMB/CIFS file share (create validates + sizes from the share). The password
/// travels as a Secret, not plaintext device-config.
/// </remarks>
public static void CreateSmbSr(string url, string user, string password, string server, string share,
    string smbUsername, string smbPassword, string srName = "sdk-example-smb")
{
    const long GiB = 1024L * 1024 * 1024;
    var session = Connect(url, user, password);
    var host = Host.get_all(session)[0];

    var secret = Secret.create(session, new Secret
    {
        value = smbPassword,
        other_config = new Dictionary<string, string>(),
    });
    var dc = new Dictionary<string, string>
    {
        // server is the share as one UNC path, //server/share: the SMB driver has no separate serverpath.
        ["server"] = $"//{server}{share}",
        ["username"] = smbUsername,
        ["password_secret"] = Secret.get_uuid(session, secret),
    };
    var sr = SR.create(session, host, dc, 0, srName, "SMB SR created by the SDK example",
        "smb", "user", true, new Dictionary<string, string>());
    Console.WriteLine($"Created SR: {SR.get_uuid(session, sr)} ({SR.get_physical_size(session, sr) / GiB} GiB)");
    DetachAndForgetSr(session, sr);
    Secret.destroy(session, secret);
    Console.WriteLine("OK: create-smb-sr");
    session.logout();
}
```

<details><summary>Example output</summary>

```text
Created SR: 00000001-0000-0000-8c0a-000000000000 (512 GiB)
OK: create-smb-sr
```

</details>

## Go

Source: [`go/create_smb_sr.go`](../../go/create_smb_sr.go)

```go
package main

import (
	"fmt"

	"go/xenapi"
)

// createSmbSr - Create an SMB SR.
//
// Connect a shared storage repository to an SMB/CIFS file share, passing the server, share path and
// credentials (the password as a secret, never in plain text).
//
// Connect a shared SR to an SMB/CIFS file share. The password travels as a Secret, not plaintext
// device-config.
func createSmbSr(url, user, password, server, share, smbUsername, smbPassword, srName string) {
	const GiB = 1024 * 1024 * 1024
	session := connect(url, user, password)
	hosts, err := xenapi.Host.GetAll(session)
	check(err)
	host := hosts[0]

	secret, err := xenapi.Secret.Create(session, xenapi.SecretRecord{
		Value: smbPassword, OtherConfig: map[string]string{},
	})
	check(err)
	secretUUID, err := xenapi.Secret.GetUUID(session, secret)
	check(err)
	// server is the share as one UNC path, //server/share: the SMB driver has no separate serverpath.
	dc := map[string]string{
		"server": "//" + server + share, "username": smbUsername,
		"password_secret": secretUUID,
	}
	sr, err := xenapi.SR.Create(session, host, dc, 0, srName,
		"SMB SR created by the SDK example", "smb", "user", true, map[string]string{})
	check(err)
	size, _ := xenapi.SR.GetPhysicalSize(session, sr)
	uuid, _ := xenapi.SR.GetUUID(session, sr)
	fmt.Printf("Created SR: %s (%d GiB)\n", uuid, size/GiB)
	detachAndForgetSR(session, sr)
	check(xenapi.Secret.Destroy(session, secret))
	fmt.Println("OK: create-smb-sr")
	session.Logout()
}
```

<details><summary>Example output</summary>

```text
Created SR: 00000001-0000-0000-100b-000000000000 (512 GiB)
OK: create-smb-sr
```

</details>

## Java

Source: [`java/src/main/java/com/xenserver/samples/storage/CreateSmbSr.java`](../../java/src/main/java/com/xenserver/samples/storage/CreateSmbSr.java)

```java
package com.xenserver.samples.storage;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.Host;
import com.xensource.xenapi.SR;
import com.xensource.xenapi.Secret;
import com.xensource.xenapi.Session;

import java.util.Map;

import static com.xenserver.samples.Helpers.detachAndForgetSr;
import static com.xenserver.samples.PoolConnection.connect;

public final class CreateSmbSr {
    private CreateSmbSr() {
    }

    /**
     * Create an SMB SR.
     *
     * <p>Connect a shared storage repository to an SMB/CIFS file share, passing the server, share path and
     * credentials (the password as a secret, never in plain text).
     *
     * <p>Connect a shared SR to an SMB/CIFS file share (create validates + sizes from the share). The
     * password travels as a Secret, not plaintext device-config.
     *
     * <p>Run it:
     *
     * <pre>{@code
     * CreateSmbSr.run("https://xenserver", "root", password, "192.0.2.40", "/vmstore", "Administrator",
     * "Password1", "sdk-example-smb");
     * }</pre>
     */
    public static void run(String url, String user, String password, String server, String share,
            String smbUsername, String smbPassword, String srName) throws Exception {
        final long GiB = 1024L * 1024 * 1024;
        Connection conn = connect(url, user, password);
        try {
            Host host = Host.getAllRecords(conn).keySet().iterator().next();
            Secret.Record secretRec = new Secret.Record();
            secretRec.value = smbPassword;
            secretRec.otherConfig = new java.util.HashMap<>();
            Secret secret = Secret.create(conn, secretRec);

            Map<String, String> dc = new java.util.HashMap<>();
            // server is the share as one UNC path, //server/share: the SMB driver has no separate serverpath.
            dc.put("server", "//" + server + share);
            dc.put("username", smbUsername);
            dc.put("password_secret", secret.getUuid(conn));
            SR sr = SR.create(conn, host, dc, 0L, srName, "SMB SR created by the SDK example",
                "smb", "user", true, new java.util.HashMap<>());
            System.out.println("Created SR: " + sr.getUuid(conn) + " (" + sr.getPhysicalSize(conn) / GiB + " GiB)");
            detachAndForgetSr(conn, sr);
            secret.destroy(conn);
            System.out.println("OK: create-smb-sr");
        } finally {
            Session.logout(conn);
        }
    }
}
```

<details><summary>Example output</summary>

```text
Created SR: 00000001-0000-0000-740a-000000000000 (512 GiB)
OK: create-smb-sr
```

</details>
