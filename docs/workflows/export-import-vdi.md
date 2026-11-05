<!-- Generated from workflows.json, the example sources and a run of each example. Edit those, not this file. -->

# Copy a disk's contents

Upload data into a virtual disk, download the disk's raw contents and copy them into a second disk, then check that the copy matches. Disk contents travel as HTTP transfers alongside the API.

Workflow `export-import-vdi`. [All workflows](README.md) · [Connecting](connecting.md)

## C# (.NET)

Source: [`csharp/Storage/ExportImportVdi.cs`](../../csharp/Storage/ExportImportVdi.cs)

```csharp
/// <summary>
/// Upload data into a virtual disk, download the disk's raw contents and copy them into a second disk,
/// then check that the copy matches. Disk contents travel as HTTP transfers alongside the API.
/// </summary>
/// <example>
/// <code>
/// Workflows.ExportImportVdi("https://xenserver", "root", password, "Shared NFS");
/// </code>
/// </example>
/// <remarks>
/// A disk's contents are not XenAPI calls: GET /export_raw_vdi reads them and PUT /import_raw_vdi writes
/// them, both alongside the API with the session id in the query string. format=raw is every byte of the
/// disk, so a raw export is as large as the disk's virtual size (format=vhd sends only the allocated
/// blocks). Name a task in task_id to learn how the transfer ended: an HTTP 200 only means the server
/// accepted the request.
/// </remarks>
public static void ExportImportVdi(string url, string user, string password, string srName)
{
    var session = Connect(url, user, password);
    var sr = SrByName(session, srName);
    const long size = 8 * 1024 * 1024;

    string NewDisk(string name) => VDI.create(session, new VDI
    {
        name_label = name,
        SR = new XenRef<SR>(sr),
        virtual_size = size,
        type = vdi_type.user,
        sharable = false,
        read_only = false,
        other_config = new Dictionary<string, string>(),
    }).opaque_ref;

    // One raw transfer of a disk's contents, waiting for its task to finish.
    byte[] Transfer(HttpMethod method, string path, string vdi, byte[] data = null)
    {
        var task = Task.create(session, $"sdk-example-{path}", "").opaque_ref;
        try
        {
            using var client = InsecureHttpClient();
            using var request = new HttpRequestMessage(method,
                $"{url}/{path}?session_id={session.opaque_ref}&task_id={task}&vdi={vdi}&format=raw");
            if (data != null) request.Content = new ByteArrayContent(data);
            using var response = client.Send(request);
            response.EnsureSuccessStatusCode();
            var body = response.Content.ReadAsByteArrayAsync().Result;

            while (Task.get_status(session, task) == task_status_type.pending)
                System.Threading.Thread.Sleep(500);
            if (Task.get_status(session, task) != task_status_type.success)
                throw new Exception($"{path} failed: {string.Join(", ", Task.get_error_info(session, task))}");
            return body;
        }
        finally
        {
            Task.destroy(session, task);
        }
    }

    var original = NewDisk("sdk-example-raw-source");
    var copy = NewDisk("sdk-example-raw-copy");
    try
    {
        var data = RandomNumberGenerator.GetBytes((int)size);
        Transfer(HttpMethod.Put, "import_raw_vdi", original, data);
        Console.WriteLine($"Uploaded {size / (1024 * 1024)} MiB into {VDI.get_name_label(session, original)}");

        var exported = Transfer(HttpMethod.Get, "export_raw_vdi", original);
        Console.WriteLine($"Downloaded {exported.Length / (1024 * 1024)} MiB of raw contents");

        Transfer(HttpMethod.Put, "import_raw_vdi", copy, exported);
        Console.WriteLine($"Copied them into {VDI.get_name_label(session, copy)}");

        var same = SHA256.HashData(Transfer(HttpMethod.Get, "export_raw_vdi", copy))
            .SequenceEqual(SHA256.HashData(data));
        Console.WriteLine($"The copy {(same ? "matches" : "DIFFERS FROM")} the original");
        if (!same) throw new Exception("the copied disk does not match the data uploaded");
    }
    finally
    {
        VDI.destroy(session, original);
        VDI.destroy(session, copy);
    }
    Console.WriteLine("OK: export-import-vdi");
    session.logout();
}
```

<details><summary>Sample output</summary>

```text
Uploaded 8 MiB into sdk-example-raw-source
Downloaded 8 MiB of raw contents
Copied them into sdk-example-raw-copy
The copy matches the original
OK: export-import-vdi
```

</details>

## Python

Source: [`python/storage/export_import_vdi.py`](../../python/storage/export_import_vdi.py)

```python
"""Copy a disk's contents (raw export and import).

Upload data into a virtual disk, download the disk's raw contents and copy them into a second disk,
then check that the copy matches. Disk contents travel as HTTP transfers alongside the API.

Run it::

    export_import_vdi("https://xenserver", "root", password, "Shared NFS")
"""

import hashlib
import os
import ssl
import time
import urllib.request

from connection import connect
from helpers import sr_by_name

MIB = 1024 * 1024


def export_import_vdi(url, username, password, sr_name):
    """Fill a new disk on sr_name with data, then copy it to a second disk through its raw contents.

    A disk's contents are not XenAPI calls: GET /export_raw_vdi reads them and PUT /import_raw_vdi
    writes them, both alongside the API with the session id in the query string. format=raw is every
    byte of the disk, so a raw export is as large as the disk's virtual size (format=vhd sends only
    the allocated blocks). Name a task in task_id to learn how the transfer ended: an HTTP 200 only
    means the server accepted the request."""
    session = connect(url, username, password)
    x = session.xenapi
    sr = sr_by_name(session, sr_name)
    ctx = ssl._create_unverified_context()

    def new_disk(name, size):
        return x.VDI.create({"name_label": name, "SR": sr, "virtual_size": str(size), "type": "user",
                             "sharable": False, "read_only": False, "other_config": {}})

    def transfer(method, path, vdi, data=None):
        """One raw transfer of vdi's contents, waiting for its task to finish."""
        task = x.task.create("sdk-example-%s" % path, "")
        try:
            request = urllib.request.Request(
                "%s/%s?session_id=%s&task_id=%s&vdi=%s&format=raw" % (url, path, session._session, task, vdi),
                data=data, method=method)
            with urllib.request.urlopen(request, context=ctx) as response:
                body = response.read()
            while x.task.get_status(task) == "pending":
                time.sleep(0.5)
            if x.task.get_status(task) != "success":
                raise RuntimeError("%s failed: %s" % (path, x.task.get_error_info(task)))
        finally:
            x.task.destroy(task)
        return body

    size = 8 * MIB
    original = new_disk("sdk-example-raw-source", size)
    copy = new_disk("sdk-example-raw-copy", size)
    try:
        data = os.urandom(size)
        transfer("PUT", "import_raw_vdi", original, data)
        print("Uploaded %d MiB into %s" % (size // MIB, x.VDI.get_name_label(original)))

        exported = transfer("GET", "export_raw_vdi", original)
        print("Downloaded %d MiB of raw contents" % (len(exported) // MIB))

        transfer("PUT", "import_raw_vdi", copy, exported)
        print("Copied them into %s" % x.VDI.get_name_label(copy))

        same = hashlib.sha256(transfer("GET", "export_raw_vdi", copy)).digest() == hashlib.sha256(data).digest()
        print("The copy %s the original" % ("matches" if same else "DIFFERS FROM"))
        if not same:
            raise RuntimeError("the copied disk does not match the data uploaded")
    finally:
        for vdi in (original, copy):
            x.VDI.destroy(vdi)
    print("OK: export-import-vdi")
    session.logout()
```

<details><summary>Sample output</summary>

```text
Uploaded 8 MiB into sdk-example-raw-source
Downloaded 8 MiB of raw contents
Copied them into sdk-example-raw-copy
The copy matches the original
OK: export-import-vdi
```

</details>

## Java

Source: [`java/src/main/java/com/xenserver/samples/storage/ExportImportVdi.java`](../../java/src/main/java/com/xenserver/samples/storage/ExportImportVdi.java)

```java
package com.xenserver.samples.storage;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.SR;
import com.xensource.xenapi.Session;
import com.xensource.xenapi.Task;
import com.xensource.xenapi.Types;
import com.xensource.xenapi.VDI;

import org.apache.hc.client5.http.classic.methods.HttpGet;
import org.apache.hc.client5.http.classic.methods.HttpPut;
import org.apache.hc.client5.http.classic.methods.HttpUriRequestBase;
import org.apache.hc.client5.http.impl.classic.CloseableHttpClient;
import org.apache.hc.core5.http.io.entity.ByteArrayEntity;
import org.apache.hc.core5.http.io.entity.EntityUtils;

import java.security.MessageDigest;
import java.security.SecureRandom;
import java.util.Arrays;
import java.util.HashMap;

import static com.xenserver.samples.Helpers.srByName;
import static com.xenserver.samples.PoolConnection.connect;
import static com.xenserver.samples.PoolConnection.trustingHttpClient;

public final class ExportImportVdi {
    private ExportImportVdi() {
    }

    private static final long SIZE = 8L * 1024 * 1024;

    /**
     * Copy a disk's contents.
     *
     * <p>Upload data into a virtual disk, download the disk's raw contents and copy them into a second disk,
     * then check that the copy matches. Disk contents travel as HTTP transfers alongside the API.
     *
     * <p>A disk's contents are not XenAPI calls: GET /export_raw_vdi reads them and PUT /import_raw_vdi
     * writes them, both alongside the API with the session id in the query string. format=raw is every
     * byte of the disk, so a raw export is as large as the disk's virtual size (format=vhd sends only the
     * allocated blocks). Name a task in task_id to learn how the transfer ended: an HTTP 200 only means the
     * server accepted the request.
     *
     * <p>Run it:
     *
     * <pre>{@code
     * ExportImportVdi.run("https://xenserver", "root", password, "Shared NFS");
     * }</pre>
     */
    public static void run(String url, String user, String password, String srName) throws Exception {
        Connection conn = connect(url, user, password);
        SR sr = srByName(conn, srName, false);

        VDI original = newDisk(conn, sr, "sdk-example-raw-source");
        VDI copy = newDisk(conn, sr, "sdk-example-raw-copy");
        try {
            byte[] data = new byte[(int) SIZE];
            new SecureRandom().nextBytes(data);
            transfer(conn, url, new HttpPut(url), "import_raw_vdi", original, data);
            System.out.printf("Uploaded %d MiB into %s%n", SIZE / (1024 * 1024), original.getNameLabel(conn));

            byte[] exported = transfer(conn, url, new HttpGet(url), "export_raw_vdi", original, null);
            System.out.printf("Downloaded %d MiB of raw contents%n", exported.length / (1024 * 1024));

            transfer(conn, url, new HttpPut(url), "import_raw_vdi", copy, exported);
            System.out.println("Copied them into " + copy.getNameLabel(conn));

            MessageDigest sha256 = MessageDigest.getInstance("SHA-256");
            boolean same = Arrays.equals(
                sha256.digest(transfer(conn, url, new HttpGet(url), "export_raw_vdi", copy, null)),
                sha256.digest(data));
            System.out.println("The copy " + (same ? "matches" : "DIFFERS FROM") + " the original");
            if (!same) throw new RuntimeException("the copied disk does not match the data uploaded");
        } finally {
            original.destroy(conn);
            copy.destroy(conn);
        }
        System.out.println("OK: export-import-vdi");
        Session.logout(conn);
    }

    private static VDI newDisk(Connection conn, SR sr, String name) throws Exception {
        VDI.Record record = new VDI.Record();
        record.nameLabel = name;
        record.SR = sr;
        record.virtualSize = SIZE;
        record.type = Types.VdiType.USER;
        record.sharable = false;
        record.readOnly = false;
        record.otherConfig = new HashMap<>();
        return VDI.create(conn, record);
    }

    /** One raw transfer of a disk's contents, waiting for its task to finish. */
    private static byte[] transfer(Connection conn, String url, HttpUriRequestBase request, String path, VDI vdi,
                                   byte[] data) throws Exception {
        Task task = Task.create(conn, "sdk-example-" + path, "");
        try {
            request.setUri(new java.net.URI(url + "/" + path + "?session_id=" + conn.getSessionReference()
                + "&task_id=" + task.toWireString() + "&vdi=" + vdi.toWireString() + "&format=raw"));
            if (data != null) request.setEntity(new ByteArrayEntity(data, null));
            byte[] body;
            try (CloseableHttpClient http = trustingHttpClient()) {
                body = http.execute(request, response -> {
                    byte[] received = EntityUtils.toByteArray(response.getEntity());
                    if (response.getCode() < 200 || response.getCode() >= 300) {
                        throw new RuntimeException(path + ": HTTP " + response.getCode() + ": "
                            + new String(received, java.nio.charset.StandardCharsets.UTF_8));
                    }
                    return received;
                });
            }
            while (task.getStatus(conn) == Types.TaskStatusType.PENDING) Thread.sleep(500);
            if (task.getStatus(conn) != Types.TaskStatusType.SUCCESS)
                throw new RuntimeException(path + " failed: " + task.getErrorInfo(conn));
            return body;
        } finally {
            task.destroy(conn);
        }
    }
}
```

<details><summary>Sample output</summary>

```text
Uploaded 8 MiB into sdk-example-raw-source
Downloaded 8 MiB of raw contents
Copied them into sdk-example-raw-copy
The copy matches the original
OK: export-import-vdi
```

</details>

## Go

Source: [`go/export_import_vdi.go`](../../go/export_import_vdi.go)

```go
package main

import (
	"bytes"
	"crypto/rand"
	"crypto/sha256"
	"fmt"
	"io"
	"net/http"
	"time"

	"go/xenapi"
)

// exportImportVdi - Copy a disk's contents.
//
// Upload data into a virtual disk, download the disk's raw contents and copy them into a second disk,
// then check that the copy matches. Disk contents travel as HTTP transfers alongside the API.
//
// A disk's contents are not XenAPI calls: GET /export_raw_vdi reads them and PUT /import_raw_vdi
// writes them, both alongside the API with the session id in the query string. format=raw is every
// byte of the disk, so a raw export is as large as the disk's virtual size (format=vhd sends only the
// allocated blocks). Name a task in task_id to learn how the transfer ended: an HTTP 200 only means
// the server accepted the request.
//
// Run it:
//
//	exportImportVdi("https://xenserver", "root", password, "Shared NFS")
func exportImportVdi(url, user, password, srName string) {
	session := connect(url, user, password)
	defer session.Logout()
	// The Go binding keeps its own session id private, so log in once more for the HTTP transfers.
	sid := rawLogin(url, user, password)
	defer rawRPC(url, "session.logout", sid)
	sr := srByName(session, srName, false)
	const size = 8 * 1024 * 1024

	newDisk := func(name string) xenapi.VDIRef {
		vdi, err := xenapi.VDI.Create(session, xenapi.VDIRecord{
			NameLabel:   name,
			SR:          sr,
			VirtualSize: size,
			Type:        xenapi.VdiTypeUser,
			OtherConfig: map[string]string{},
		})
		check(err)
		return vdi
	}

	// One raw transfer of a disk's contents, waiting for its task to finish.
	transfer := func(method, path string, vdi xenapi.VDIRef, data []byte) []byte {
		task, err := xenapi.Task.Create(session, "sdk-example-"+path, "")
		check(err)
		defer xenapi.Task.Destroy(session, task)
		var body io.Reader
		if data != nil {
			body = bytes.NewReader(data)
		}
		request, err := http.NewRequest(method,
			fmt.Sprintf("%s/%s?session_id=%s&task_id=%s&vdi=%s&format=raw", url, path, sid, task, vdi), body)
		check(err)
		response, err := insecureClient().Do(request)
		check(err)
		received, err := io.ReadAll(response.Body)
		response.Body.Close()
		check(err)
		if response.StatusCode < 200 || response.StatusCode >= 300 {
			panic(fmt.Sprintf("%s: HTTP %s: %s", path, response.Status, received))
		}

		for {
			status, err := xenapi.Task.GetStatus(session, task)
			check(err)
			if status != xenapi.TaskStatusTypePending {
				break
			}
			time.Sleep(500 * time.Millisecond)
		}
		if status, _ := xenapi.Task.GetStatus(session, task); status != xenapi.TaskStatusTypeSuccess {
			errInfo, _ := xenapi.Task.GetErrorInfo(session, task)
			panic(fmt.Sprintf("%s failed: %v", path, errInfo))
		}
		return received
	}

	original := newDisk("sdk-example-raw-source")
	copied := newDisk("sdk-example-raw-copy")
	defer func() {
		check(xenapi.VDI.Destroy(session, original))
		check(xenapi.VDI.Destroy(session, copied))
	}()

	data := make([]byte, size)
	_, err := rand.Read(data)
	check(err)
	transfer(http.MethodPut, "import_raw_vdi", original, data)
	name, _ := xenapi.VDI.GetNameLabel(session, original)
	fmt.Printf("Uploaded %d MiB into %s\n", size/(1024*1024), name)

	exported := transfer(http.MethodGet, "export_raw_vdi", original, nil)
	fmt.Printf("Downloaded %d MiB of raw contents\n", len(exported)/(1024*1024))

	transfer(http.MethodPut, "import_raw_vdi", copied, exported)
	name, _ = xenapi.VDI.GetNameLabel(session, copied)
	fmt.Printf("Copied them into %s\n", name)

	same := sha256.Sum256(transfer(http.MethodGet, "export_raw_vdi", copied, nil)) == sha256.Sum256(data)
	if !same {
		fmt.Println("The copy DIFFERS FROM the original")
		panic("the copied disk does not match the data uploaded")
	}
	fmt.Println("The copy matches the original")
	fmt.Println("OK: export-import-vdi")
}
```

<details><summary>Sample output</summary>

```text
Uploaded 8 MiB into sdk-example-raw-source
Downloaded 8 MiB of raw contents
Copied them into sdk-example-raw-copy
The copy matches the original
OK: export-import-vdi
```

</details>

## PowerShell

Source: [`powershell/Storage/Invoke-ExportImportVdi.ps1`](../../powershell/Storage/Invoke-ExportImportVdi.ps1)

```powershell
function Invoke-ExportImportVdi {
    <#
    .SYNOPSIS
        Copy a disk's contents.
    .DESCRIPTION
        Upload data into a virtual disk, download the disk's raw contents and copy them into a second disk,
        then check that the copy matches. Disk contents travel as HTTP transfers alongside the API.

        A disk's contents are not XenAPI calls: GET /export_raw_vdi reads them and PUT /import_raw_vdi
        writes them, both alongside the API with the session id in the query string. format=raw is every
        byte of the disk, so a raw export is as large as the disk's virtual size (format=vhd sends only the
        allocated blocks). Name a task in task_id to learn how the transfer ended: an HTTP 200 only means
        the server accepted the request.
    .EXAMPLE
        Invoke-ExportImportVdi -Url https://xenserver -UserName root -Password $password -SrName 'Shared NFS'
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password,
        [string]$SrName = 'Shared NFS'
    )
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password
    $sr = Get-XenSR -Name $SrName | Select-Object -First 1
    if (-not $sr) { throw "No SR named '$SrName' was found." }
    $size = 8MB

    $original = New-XenVDI -NameLabel "sdk-example-raw-source" -SR $sr -VirtualSize $size `
        -Type user -Sharable $false -ReadOnly $false -PassThru
    $copy = New-XenVDI -NameLabel "sdk-example-raw-copy" -SR $sr -VirtualSize $size `
        -Type user -Sharable $false -ReadOnly $false -PassThru
    # Files, not byte arrays, for the transfers: -InFile and -OutFile stream them.
    $source = Join-Path ([IO.Path]::GetTempPath()) "sdk-example-raw-$([guid]::NewGuid().Guid)"
    $exported = "$source.exported"
    try {
        $data = [byte[]]::new($size)
        [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($data)
        [IO.File]::WriteAllBytes($source, $data)

        Send-RawVdi -Session $session -Url $Url -Vdi $original -Path $source
        Write-Host "Uploaded $($size / 1MB) MiB into $($original.name_label)"

        Receive-RawVdi -Session $session -Url $Url -Vdi $original -Path $exported
        Write-Host "Downloaded $((Get-Item $exported).Length / 1MB) MiB of raw contents"

        Send-RawVdi -Session $session -Url $Url -Vdi $copy -Path $exported
        Write-Host "Copied them into $($copy.name_label)"

        Receive-RawVdi -Session $session -Url $Url -Vdi $copy -Path $exported
        $same = (Get-FileHash $exported -Algorithm SHA256).Hash -eq (Get-FileHash $source -Algorithm SHA256).Hash
        Write-Host "The copy $(if ($same) { 'matches' } else { 'DIFFERS FROM' }) the original"
        if (-not $same) { throw "the copied disk does not match the data uploaded" }
    }
    finally {
        Remove-Item $source, $exported -ErrorAction SilentlyContinue
        $original, $copy | ForEach-Object { Remove-XenVDI -Ref $_.opaque_ref }
    }
    Write-Host "OK: export-import-vdi"
    $session | Disconnect-XenServer
}

function Send-RawVdi {
    <#
    .SYNOPSIS
        PUT /import_raw_vdi: write a file's bytes into a disk, waiting for the transfer's task.
    #>
    param($Session, [string]$Url, $Vdi, [string]$Path)
    Invoke-RawVdiTransfer -Session $Session -Url $Url -Vdi $Vdi -Path $Path -Method Put -Endpoint import_raw_vdi
}

function Receive-RawVdi {
    <#
    .SYNOPSIS
        GET /export_raw_vdi: read a disk's raw contents into a file, waiting for the transfer's task.
    #>
    param($Session, [string]$Url, $Vdi, [string]$Path)
    Invoke-RawVdiTransfer -Session $Session -Url $Url -Vdi $Vdi -Path $Path -Method Get -Endpoint export_raw_vdi
}

function Invoke-RawVdiTransfer {
    <#
    .SYNOPSIS
        One raw transfer of a disk's contents, waiting for its task to finish.
    #>
    param($Session, [string]$Url, $Vdi, [string]$Path, [string]$Method, [string]$Endpoint)
    $task = New-XenTask -Label "sdk-example-$Endpoint" -Description "" -PassThru
    try {
        $uri = "$Url/$Endpoint" + "?session_id=$($Session.opaque_ref)&task_id=$($task.opaque_ref)" +
            "&vdi=$($Vdi.opaque_ref)&format=raw"
        if ($Method -eq 'Put') { Invoke-WebRequest -Uri $uri -Method Put -InFile $Path -UseBasicParsing | Out-Null }
        else { Invoke-WebRequest -Uri $uri -OutFile $Path -UseBasicParsing }
        while ((Get-XenTask -Ref $task.opaque_ref).status -eq 'pending') { Start-Sleep -Milliseconds 500 }
        $finished = Get-XenTask -Ref $task.opaque_ref
        if ($finished.status -ne 'success') { throw "$Endpoint failed: $($finished.error_info -join ' ')" }
    }
    finally {
        Remove-XenTask -Ref $task.opaque_ref
    }
}
```

<details><summary>Sample output</summary>

```text
Uploaded 8 MiB into sdk-example-raw-source
Downloaded 8 MiB of raw contents
Copied them into sdk-example-raw-copy
The copy matches the original
OK: export-import-vdi
```

</details>

## xe CLI

Source: [`cli/storage/export-import-vdi.sh`](../../cli/storage/export-import-vdi.sh)

```bash
# Copy a disk's contents.
#
# Upload data into a virtual disk, download the disk's raw contents and copy them into a second disk, then
# check that the copy matches. Disk contents travel as HTTP transfers alongside the API.
#
# Run it:
#   ./workflows.sh export-import-vdi https://xenserver root "$password"
#
# Optional key=value arguments (default):
#   sr_name (Shared NFS)

# vdi-import and vdi-export move a disk's contents: xe does the HTTP transfer itself, against
# /import_raw_vdi or /export_raw_vdi, and waits for the server to finish with it. format=raw is every byte
# of the disk, so a raw export is as large as the disk's virtual size (format=vhd sends only the allocated
# blocks).
export_import_vdi() {
    local sr_name sr original copy
    sr_name=$(param sr_name "Shared NFS")
    sr=$(xe sr-list name-label="$sr_name" --minimal)
    sr=$(first_csv "$sr")
    original=$(xe vdi-create sr-uuid=$sr name-label=sdk-example-raw-source virtual-size=8MiB type=user)
    copy=$(xe vdi-create sr-uuid=$sr name-label=sdk-example-raw-copy virtual-size=8MiB type=user)

    # Relative to the working directory: xe.exe and this script must agree on the path, and a Windows
    # temp directory spelled with backslashes would not survive the trip through both.
    local data=cli-raw-source.bin exported=cli-raw-exported.bin
    trap 'rm -f "$data" "$exported"' EXIT
    head -c $((8 * 1024 * 1024)) /dev/urandom > "$data"

    xe vdi-import uuid=$original filename="$data" format=raw
    echo "Uploaded 8 MiB into sdk-example-raw-source"

    xe vdi-export uuid=$original filename="$exported" format=raw
    echo "Downloaded $(( $(wc -c < "$exported") / 1024 / 1024 )) MiB of raw contents"

    xe vdi-import uuid=$copy filename="$exported" format=raw
    echo "Copied them into sdk-example-raw-copy"

    rm -f "$exported"
    xe vdi-export uuid=$copy filename="$exported" format=raw
    if cmp -s "$data" "$exported"; then
        echo "The copy matches the original"
    else
        echo "The copy DIFFERS FROM the original" >&2
        exit 1
    fi

    xe vdi-destroy uuid=$original
    xe vdi-destroy uuid=$copy
    echo "OK: export-import-vdi"
}
```
