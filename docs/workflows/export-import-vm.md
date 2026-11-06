<!-- Generated from workflows.json, the example sources and a run of each example. Edit those, not this file. -->

# Export and import a VM

Export a VM to an XVA file and import it back as a new one. These are HTTP transfers alongside the API rather than API calls, so the session id travels in the query string.

Workflow `export-import-vm`. [All workflows](README.md) · [Connecting](connecting.md)

## PowerShell

Source: [`powershell/VirtualMachines/Invoke-ExportImportVm.ps1`](../../powershell/VirtualMachines/Invoke-ExportImportVm.ps1)

```powershell
function Invoke-ExportImportVm {
    <#
    .SYNOPSIS
        Export and import a VM.
    .DESCRIPTION
        Export a VM to an XVA file and import it back as a new one. These are HTTP transfers alongside the
        API rather than API calls, so the session id travels in the query string.
    .EXAMPLE
        Invoke-ExportImportVm -Url https://xenserver -UserName root -Password $password -VmName db-01
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password,
        [string]$VmName = 'db-01'
    )
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password

    # Name the VM: an export carries every block of its disks, so which VM matters (a large one takes a
    # long time, and fills the disk). Only a halted VM can be exported: its disks must not be changing
    # underneath the copy.
    $vm = Get-XenVM -Name $VmName |
        Where-Object { -not $_.is_a_template -and -not $_.is_control_domain -and -not $_.is_a_snapshot } |
        Select-Object -First 1
    if (-not $vm) { throw "No VM named '$VmName' was found." }
    if ($vm.power_state -ne 'Halted') { throw "$VmName must be halted to be exported" }
    Write-Host "Exporting $VmName"

    # Export and import are HTTP transfers alongside the API rather than API calls, so the session id
    # travels in the query string. Still pure PowerShell: Connect-Example has already trusted the
    # server's certificate.
    # A unique file, not a fixed name: an export is a real file on disk and two of them running at
    # once would otherwise fight over it.
    $path = Join-Path ([IO.Path]::GetTempPath()) "sdk-example-export-$([guid]::NewGuid().Guid).xva"
    try {
        # Stream both directions: -OutFile/-InFile stream to and from the file rather than buffering the
        # whole transfer in memory, as a real VM's export can be gigabytes.
        Invoke-WebRequest -Uri "$Url/export?session_id=$($session.opaque_ref)&uuid=$($vm.uuid)" `
            -OutFile $path -UseBasicParsing
        Write-Host ("  wrote {0:N1} MiB to {1}" -f ((Get-Item $path).Length / 1MB), (Split-Path $path -Leaf))

        # An XVA is a tar: ova.xml describes the VM, and the disk blocks follow in 1 MiB pieces, each with
        # its own checksum.
        $names = Get-TarEntryName -Path $path
        Write-Host ("  archive holds {0} and {1} disk block(s)" -f
            $names[0], (@($names | Where-Object { -not $_.EndsWith('.checksum') }).Count - 1))

        # The imported VM's ref is NOT in the /import response body on a real host - the only place it
        # appears is the task named in the task_id query parameter, so create one, pass it, and read the
        # task's result once the upload finishes, the same pattern backup-host-config/wait-for-task use.
        $task = New-XenTask -Label 'vm_import' -Description "importing $VmName back" -PassThru
        try {
            Invoke-WebRequest -Uri "$Url/import?session_id=$($session.opaque_ref)&task_id=$($task.opaque_ref)" `
                -Method Put -InFile $path -UseBasicParsing | Out-Null
            while ((Get-XenTask -Ref $task).status -eq 'pending') { Start-Sleep -Milliseconds 500 }
            $finished = Get-XenTask -Ref $task
            if ($finished.status -ne 'success') { throw "import failed: $($finished.error_info -join ' ')" }
            # The result lists the imported VMs (<value><array><data>OpaqueRef:...</data></array></value>
            # on a real host), so take the first reference in it.
            $imported = [regex]::Match($finished.result, 'OpaqueRef:[^<]+').Value
        }
        finally {
            Remove-XenTask -Ref $task
        }
        Write-Host "  imported as $((Get-XenVM -Ref $imported).name_label)"

        # The import brought its own disks along; destroy those too, not just the VM record.
        Remove-VmAndDisks -Ref $imported
        Write-Host "OK: export-import-vm"
    }
    finally {
        # Always clean up the file, on failure too: a real export is gigabytes, not worth leaving behind.
        Remove-Item $path -ErrorAction SilentlyContinue
    }
    $session | Disconnect-XenServer
}

function Get-TarEntryName {
    <#
    .SYNOPSIS
        A tar's entry names, read from the format itself.
    .DESCRIPTION
        The name is the first 100 bytes of each 512-byte header and the size is octal at offset 124, with
        every file padded to the next 512-byte boundary.
    #>
    param([Parameter(Mandatory = $true)][string]$Path)
    $stream = [IO.File]::OpenRead($Path)
    try {
        $names = @()
        $header = New-Object byte[] 512
        while ($stream.Read($header, 0, 512) -eq 512) {
            $name = ([Text.Encoding]::ASCII.GetString($header, 0, 100) -replace "`0.*$", '').Trim()
            if (-not $name) { break }        # the end-of-archive marker
            $names += $name
            $octal = ([Text.Encoding]::ASCII.GetString($header, 124, 12) -replace "`0.*$", '').Trim()
            $size = if ($octal) { [Convert]::ToInt64($octal, 8) } else { 0 }
            $stream.Seek([math]::Ceiling($size / 512) * 512, [IO.SeekOrigin]::Current) | Out-Null
        }
        return $names
    }
    finally { $stream.Dispose() }
}
```

<details><summary>Example output</summary>

```text
Exporting db-01
  wrote 4.0 MiB to sdk-example-export-a2765405-93d9-4238-95ca-a7e7180c2d12.xva
  archive holds ova.xml and 4 disk block(s)
  imported as db-01 (imported)
OK: export-import-vm
```

</details>

## xe CLI

Source: [`cli/virtual-machines/export-import-vm.sh`](../../cli/virtual-machines/export-import-vm.sh)

```bash
# Export and import a VM.
#
# Export a VM to an XVA file and import it back as a new one. These are HTTP transfers alongside the API
# rather than API calls, so the session id travels in the query string.
#
# Run it:
#   ./workflows.sh export-import-vm https://xenserver root "$password"
#
# Optional key=value arguments (default):
#   vm_name (db-01)

export_import_vm() {
    vm_name=$(param vm_name "db-01")
    # Name the VM: an export carries every block of its disks, so which VM matters (a large one takes a
    # long time, and fills the disk). Only a halted VM can be exported: its disks must not be changing
    # underneath the copy.
    vm=$(vm_uuid "$vm_name")
    [ "$(xe vm-param-get uuid=$vm param-name=power-state)" = "halted" ] ||
        { echo "$vm_name must be halted to be exported" >&2; exit 1; }
    echo "Exporting $vm_name"

    # Relative to the working directory: xe.exe and this script must agree on the path, and a Windows
    # temp directory spelled with backslashes would not survive the trip through both.
    file="cli-export.xva"
    # Always clean up the file, on failure too: a real export is gigabytes, not worth leaving behind.
    trap 'rm -f "$file"' EXIT
    # xe does the HTTP transfer itself: the server answers the command by telling the client to GET
    # /export, and xe writes the file. Nothing streams down the CLI connection.
    xe vm-export uuid=$vm filename="$file"
    size=$(stat -c %s "$file" 2>/dev/null || wc -c < "$file")
    # Check the file, not xe's exit status: Windows xe.exe reports a failed transfer ("Export failed")
    # and still exits 0.
    [ "${size:-0}" -gt 0 ] || { echo "the export produced no data" >&2; exit 1; }
    echo "  wrote $((size / 1024 / 1024)) MiB to $(basename "$file")"

    # The SDK languages have to create a task, pass its id as /import?task_id=, and poll it themselves to
    # recover the imported VM's ref - a real host's /import response body doesn't carry it. xe does all of
    # that internally and hands back the new VM's uuid directly, so there is nothing extra to do here.
    imported=$(xe vm-import filename="$file")
    echo "  imported as $(xe vm-param-get uuid=$imported param-name=name-label)"

    # The import brought its own disks along; vm-uninstall destroys those too, not just the VM record.
    xe vm-uninstall uuid=$imported force=true
    echo "OK: export-import-vm"
}
```

<details><summary>Example output</summary>

```text
Exporting db-01
  wrote 4 MiB to cli-export.xva
  imported as db-01 (imported)
OK: export-import-vm
```

</details>

## Python

Source: [`python/virtual_machines/export_import_vm.py`](../../python/virtual_machines/export_import_vm.py)

```python
"""Export and import a VM.

Export a VM to an XVA file and import it back as a new one. These are HTTP transfers alongside the
API rather than API calls, so the session id travels in the query string.

Run it::

    export_import_vm("https://xenserver", "root", password, "db-01")
"""

import os
import re
import ssl
import tarfile
import tempfile
import time
import urllib.request

from connection import connect
from helpers import destroy_vm_and_disks, vm_by_name


def export_import_vm(url, username, password, vm_name):
    """Export a halted VM (vm_name) to an XVA file and import it back as a new VM.

    Export and import are not XenAPI calls: they are HTTP transfers alongside the API, and
    the session id goes in the query string. Everything else about them is ordinary HTTP -
    GET /export writes the archive, PUT /import reads one back.

    One quirk worth knowing if you write your own uploader: the server answers 200 BEFORE
    reading the body, because xapi's own clients wait for the response line before they
    start streaming. Ordinary HTTP libraries send the body first and cope with the early
    reply, so this only matters if you are working at the socket level.

    The new VM's ref is NOT in the /import response body on a real host - the only place it
    appears is the task named in the task_id query parameter, so create one, pass it, and read
    task.get_result() once the upload finishes, the same pattern backup-host-config/wait-for-task
    already use."""
    session = connect(url, username, password)
    x = session.xenapi
    session_id = session._session

    # Name the VM: an export carries every block of its disks, so which VM matters (a large one
    # takes a long time, and fills the disk). Only a halted VM can be exported: its disks must not
    # be changing underneath the copy.
    vm = vm_by_name(session, vm_name)
    if x.VM.get_power_state(vm) != "Halted":
        raise RuntimeError("%s must be halted to be exported" % vm_name)
    name = vm_name
    print("Exporting %s" % name)

    # A unique file, not a fixed name: an export is a real file on disk and two of them running at once
    # would otherwise fight over it.
    handle, path = tempfile.mkstemp(prefix="sdk-example-export-", suffix=".xva")
    os.close(handle)
    ctx = ssl._create_unverified_context()
    with urllib.request.urlopen(
            "%s/export?session_id=%s&uuid=%s" % (url, session_id, x.VM.get_uuid(vm)),
            context=ctx) as response, open(path, "wb") as out:
        exported = 0
        while True:
            chunk = response.read(1024 * 1024)
            if not chunk:
                break
            out.write(chunk)
            exported += len(chunk)
    print("  wrote %.1f MiB to %s" % (exported / (1024.0 ** 2), os.path.basename(path)))

    # An XVA is a tar: ova.xml describes the VM, and the disk blocks follow it in 1 MiB
    # pieces, each with its own checksum.
    with tarfile.open(path) as archive:
        names = archive.getnames()
    print("  archive holds %s and %d disk block(s)"
          % (names[0], len([n for n in names if not n.endswith(".checksum")]) - 1))

    task = x.task.create("vm_import", "importing %s back" % name)
    try:
        # Stream the file rather than reading it into memory: a real VM's export is gigabytes.
        with open(path, "rb") as f:
            request = urllib.request.Request(
                "%s/import?session_id=%s&task_id=%s" % (url, session_id, task),
                data=f, method="PUT", headers={"Content-Length": str(os.path.getsize(path))})
            urllib.request.urlopen(request, context=ctx).read()

        while x.task.get_status(task) == "pending":
            time.sleep(0.5)
        if x.task.get_status(task) != "success":
            raise RuntimeError("import failed: %s" % x.task.get_error_info(task))
        # The result lists the imported VMs (<value><array><data>OpaqueRef:...</data></array></value>
        # on a real host), so take the first reference in it.
        imported = re.search(r"OpaqueRef:[^<]+", x.task.get_result(task)).group(0)
    finally:
        x.task.destroy(task)
    print("  imported as %s" % x.VM.get_name_label(imported))

    # The import brought its own disks along; destroy those too, not just the VM record.
    destroy_vm_and_disks(session, imported)
    os.remove(path)
    print("OK: export-import-vm")
    session.logout()
```

<details><summary>Example output</summary>

```text
Exporting db-01
  wrote 4.0 MiB to sdk-example-export-_su1eefz.xva
  archive holds ova.xml and 4 disk block(s)
  imported as db-01 (imported)
OK: export-import-vm
```

</details>

## C# (.NET)

Source: [`csharp/VirtualMachines/ExportImportVm.cs`](../../csharp/VirtualMachines/ExportImportVm.cs)

```csharp
/// <summary>
/// Export a VM to an XVA file and import it back as a new one. These are HTTP transfers alongside the API
/// rather than API calls, so the session id travels in the query string.
/// </summary>
/// <example>
/// <code>
/// Workflows.ExportImportVm("https://xenserver", "root", password, "db-01");
/// </code>
/// </example>
public static void ExportImportVm(string url, string user, string password, string vmName)
{
    var session = Connect(url, user, password);

    // Name the VM: an export carries every block of its disks, so which VM matters (a large one
    // takes a long time, and fills the disk). Only a halted VM can be exported: its disks must not
    // be changing underneath the copy.
    var vm = VmByName(session, vmName);
    if (VM.get_power_state(session, vm) != vm_power_state.Halted)
        throw new Exception($"{vmName} must be halted to be exported");
    Console.WriteLine($"Exporting {vmName}");

    // Export and import are HTTP transfers alongside the API, not API calls, so the session id
    // travels in the query string.
    // A unique file, not a fixed name: an export is a real file on disk and two of them running at
    // once would otherwise fight over it.
    var path = Path.Combine(Path.GetTempPath(), $"sdk-example-export-{Guid.NewGuid():N}.xva");
    try
    {
        // Stream both directions: a real VM's export is gigabytes, too large to hold in memory.
        using (var client = InsecureHttpClient())
        {
            var uuid = VM.get_uuid(session, vm);
            using var response = client.GetAsync(
                $"{url}/export?session_id={session.opaque_ref}&uuid={uuid}",
                HttpCompletionOption.ResponseHeadersRead).Result;
            response.EnsureSuccessStatusCode();
            using (var httpStream = response.Content.ReadAsStreamAsync().Result)
            using (var fileStream = File.Create(path))
                httpStream.CopyTo(fileStream);
        }
        Console.WriteLine($"  wrote {new FileInfo(path).Length / (1024.0 * 1024):F1} MiB to "
                          + $"{Path.GetFileName(path)}");

        // An XVA is a tar: ova.xml describes the VM, and the disk blocks follow in 1 MiB pieces, each
        // with its own checksum.
        var names = new List<string>();
        using (var reader = new System.Formats.Tar.TarReader(File.OpenRead(path)))
            while (reader.GetNextEntry() is { } entry) names.Add(entry.Name);
        Console.WriteLine($"  archive holds {names[0]} and "
                          + $"{names.Count(n => !n.EndsWith(".checksum")) - 1} disk block(s)");

        // The imported VM's ref is NOT in the /import response body on a real host. Create a task
        // first, append &task_id=<task> to the /import URL, poll the task, and parse the ref out
        // of task.get_result() (same <value>...</value> string-strip wait-for-task already uses).
        var task = Task.create(session, "vm_import", $"importing {vmName} back").opaque_ref;
        XenRef<VM> imported;
        try
        {
            using (var client = InsecureHttpClient())
            using (var fileStream = File.OpenRead(path))
            {
                var response = client.PutAsync(
                    $"{url}/import?session_id={session.opaque_ref}&task_id={task}",
                    new StreamContent(fileStream)).Result;
                response.EnsureSuccessStatusCode();
            }

            while (Task.get_status(session, task) == task_status_type.pending)
                System.Threading.Thread.Sleep(500);
            if (Task.get_status(session, task) != task_status_type.success)
                throw new Exception($"import failed: {string.Join(", ", Task.get_error_info(session, task))}");
            // The result lists the imported VMs (<value><array><data>OpaqueRef:...</data></array></value>
            // on a real host), so take the first reference in it.
            imported = new XenRef<VM>(System.Text.RegularExpressions.Regex.Match(
                Task.get_result(session, task), "OpaqueRef:[^<]+").Value);
        }
        finally
        {
            Task.destroy(session, task);
        }
        Console.WriteLine($"  imported as {VM.get_name_label(session, imported)}");

        DestroyVmAndDisks(session, imported);
        Console.WriteLine("OK: export-import-vm");
    }
    finally
    {
        // Always clean up the file, on failure too: a real export is gigabytes, not worth leaving
        // behind in %TEMP%.
        File.Delete(path);
    }
    session.logout();
}
```

<details><summary>Example output</summary>

```text
Exporting db-01
  wrote 4.0 MiB to sdk-example-export-7e36c573dcdf4f0c957688c422c374d3.xva
  archive holds ova.xml and 4 disk block(s)
  imported as db-01 (imported)
OK: export-import-vm
```

</details>

## Go

Source: [`go/export_import_vm.go`](../../go/export_import_vm.go)

```go
package main

import (
	"archive/tar"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"time"

	"go/xenapi"
)

// exportImportVm - Export and import a VM.
//
// Export a VM to an XVA file and import it back as a new one. These are HTTP transfers alongside
// the API rather than API calls, so the session id travels in the query string.
//
// Run it:
//
//	exportImportVm("https://xenserver", "root", password, "db-01")
func exportImportVm(url, user, password, vmName string) {
	session := connect(url, user, password)
	defer session.Logout()

	// Name the VM: an export carries every block of its disks, so which VM matters (a large one takes a
	// long time, and fills the disk). Only a halted VM can be exported: its disks must not be changing
	// underneath the copy.
	vm := vmByName(session, vmName)
	powerState, err := xenapi.VM.GetPowerState(session, vm)
	check(err)
	if powerState != xenapi.VMPowerStateHalted {
		panic(fmt.Sprintf("%s must be halted to be exported", vmName))
	}
	fmt.Printf("Exporting %s\n", vmName)

	// Export and import are HTTP transfers alongside the API, not API calls, so the session id travels
	// in the query string. The Go binding keeps its own session private, so obtain one the same way the
	// RRD example does: a small JSON-RPC login of our own.
	sid := rawLogin(url, user, password)
	// A unique file, not a fixed name: an export is a real file on disk and two of them running at once
	// would otherwise fight over it.
	temp, err := os.CreateTemp("", "sdk-example-export-*.xva")
	check(err)
	path := temp.Name()
	temp.Close()
	// Always clean up the file, on failure too: a real export is gigabytes, not worth leaving behind.
	defer os.Remove(path)

	// Stream both directions: a real VM's export is gigabytes, too large to hold in memory.
	uuid, err := xenapi.VM.GetUUID(session, vm)
	check(err)
	resp, err := insecureClient().Get(fmt.Sprintf("%s/export?session_id=%s&uuid=%s", url, sid, uuid))
	check(err)
	out, err := os.Create(path)
	check(err)
	written, err := io.Copy(out, resp.Body)
	check(err)
	resp.Body.Close()
	out.Close()
	fmt.Printf("  wrote %.1f MiB to %s\n", float64(written)/(1024*1024), filepath.Base(path))

	// An XVA is a tar: ova.xml describes the VM, and the disk blocks follow in 1 MiB pieces, each with
	// its own checksum.
	names := tarNames(path)
	blocks := 0
	for _, n := range names {
		if !strings.HasSuffix(n, ".checksum") {
			blocks++
		}
	}
	fmt.Printf("  archive holds %s and %d disk block(s)\n", names[0], blocks-1)

	// The imported VM's ref is NOT in the /import response body on a real host - the only place it
	// appears is the task named in the task_id query parameter, so create one, pass it, and read
	// task.get_result() once the upload finishes (the same <value>...</value> string-strip
	// wait-for-task already uses).
	task, err := xenapi.Task.Create(session, "vm_import", "importing "+vmName+" back")
	check(err)
	defer xenapi.Task.Destroy(session, task)

	archive, err := os.Open(path)
	check(err)
	request, err := http.NewRequest(http.MethodPut,
		fmt.Sprintf("%s/import?session_id=%s&task_id=%s", url, sid, task), archive)
	check(err)
	info, err := archive.Stat()
	check(err)
	request.ContentLength = info.Size()
	putResp, err := insecureClient().Do(request)
	check(err)
	io.Copy(io.Discard, putResp.Body)
	putResp.Body.Close()
	archive.Close()

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
		panic(fmt.Sprintf("import failed: %v", errInfo))
	}
	result, err := xenapi.Task.GetResult(session, task)
	check(err)
	// The result lists the imported VMs (<value><array><data>OpaqueRef:...</data></array></value>
	// on a real host), so take the first reference in it.
	imported := xenapi.VMRef(regexp.MustCompile(`OpaqueRef:[^<]+`).FindString(result))
	name, err := xenapi.VM.GetNameLabel(session, imported)
	check(err)
	fmt.Printf("  imported as %s\n", name)

	// The import brought its own disks along; destroy those too, not just the VM record.
	destroyVMAndDisks(session, imported)
	fmt.Println("OK: export-import-vm")
}

// tarNames lists the entries of a tar archive.
func tarNames(path string) []string {
	file, err := os.Open(path)
	check(err)
	defer file.Close()
	var names []string
	reader := tar.NewReader(file)
	for {
		header, err := reader.Next()
		if err != nil {
			break
		}
		names = append(names, header.Name)
	}
	return names
}
```

<details><summary>Example output</summary>

```text
Exporting db-01
  wrote 4.0 MiB to sdk-example-export-3124867839.xva
  archive holds ova.xml and 4 disk block(s)
  imported as db-01 (imported)
OK: export-import-vm
```

</details>

## Java

Source: [`java/src/main/java/com/xenserver/samples/virtualmachines/ExportImportVm.java`](../../java/src/main/java/com/xenserver/samples/virtualmachines/ExportImportVm.java)

```java
package com.xenserver.samples.virtualmachines;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.Session;
import com.xensource.xenapi.Task;
import com.xensource.xenapi.Types;
import com.xensource.xenapi.VM;

import org.apache.hc.client5.http.classic.methods.HttpGet;
import org.apache.hc.client5.http.classic.methods.HttpPut;
import org.apache.hc.client5.http.impl.classic.CloseableHttpClient;
import org.apache.hc.core5.http.io.entity.EntityUtils;

import static com.xenserver.samples.Helpers.destroyVmAndDisks;
import static com.xenserver.samples.Helpers.vmByName;
import static com.xenserver.samples.PoolConnection.connect;
import static com.xenserver.samples.PoolConnection.trustingHttpClient;

public final class ExportImportVm {
    private ExportImportVm() {
    }

    /**
     * Export and import a VM.
     *
     * <p>Export a VM to an XVA file and import it back as a new one. These are HTTP transfers alongside
     * the API rather than API calls, so the session id travels in the query string.
     *
     * <p>Run it:
     *
     * <pre>{@code
     * ExportImportVm.run("https://xenserver", "root", password, "db-01");
     * }</pre>
     */
    public static void run(String url, String user, String password, String vmName) throws Exception {
        Connection conn = connect(url, user, password);
        try {
            // Name the VM: an export carries every block of its disks, so which VM matters (a large one
            // takes a long time, and fills the disk). Only a halted VM can be exported: its disks must
            // not be changing underneath the copy.
            VM vm = vmByName(conn, vmName);
            if (vm.getPowerState(conn) != Types.VmPowerState.HALTED)
                throw new RuntimeException(vmName + " must be halted to be exported");
            System.out.println("Exporting " + vmName);

            // Export and import are HTTP transfers alongside the API, not API calls, so the session id
            // travels in the query string.
            String session = conn.getSessionReference();
            java.io.File file = java.io.File.createTempFile("sdk-example-export", ".xva");
            try {
                // Stream both directions: a real VM's export is gigabytes, too large to hold in memory.
                HttpGet get = new HttpGet(url + "/export?session_id=" + session + "&uuid=" + vm.getUuid(conn));
                try (CloseableHttpClient http = trustingHttpClient()) {
                    http.execute(get, resp -> {
                        try (java.io.InputStream in = resp.getEntity().getContent()) {
                            java.nio.file.Files.copy(in, file.toPath(),
                                java.nio.file.StandardCopyOption.REPLACE_EXISTING);
                        }
                        return null;
                    });
                }
                System.out.printf("  wrote %.1f MiB to %s%n", file.length() / (1024.0 * 1024), file.getName());

                // An XVA is a tar: ova.xml describes the VM, and the disk blocks follow in 1 MiB pieces,
                // each with its own checksum.
                java.util.List<String> names = tarNames(file);
                long blocks = names.stream().filter(n -> !n.endsWith(".checksum")).count() - 1;
                System.out.printf("  archive holds %s and %d disk block(s)%n", names.get(0), blocks);

                // The imported VM's ref is NOT in the /import response body on a real host. Create a
                // task first, append &task_id=<task> to the /import URL, poll the task, and parse the
                // ref out of task.getResult() (same <value>...</value> string-strip wait-for-task
                // already uses). Destroy the task in a finally.
                Task task = Task.create(conn, "vm_import", "importing " + vmName + " back");
                VM importedVm;
                try {
                    HttpPut put = new HttpPut(
                        url + "/import?session_id=" + session + "&task_id=" + task.toWireString());
                    put.setEntity(new org.apache.hc.core5.http.io.entity.FileEntity(
                        file, org.apache.hc.core5.http.ContentType.APPLICATION_OCTET_STREAM));
                    try (CloseableHttpClient http = trustingHttpClient()) {
                        http.execute(put, resp -> EntityUtils.toString(resp.getEntity()));
                    }

                    while (task.getStatus(conn) == Types.TaskStatusType.PENDING) Thread.sleep(500);
                    if (task.getStatus(conn) != Types.TaskStatusType.SUCCESS)
                        throw new RuntimeException("import failed: " + task.getErrorInfo(conn));
                    // The result lists the imported VMs (<value><array><data>OpaqueRef:...</data></array></value>
                    // on a real host), so take the first reference in it.
                    java.util.regex.Matcher ref = java.util.regex.Pattern.compile("OpaqueRef:[^<]+")
                        .matcher(task.getResult(conn));
                    if (!ref.find()) throw new RuntimeException("import returned no VM: " + task.getResult(conn));
                    importedVm = new VM(ref.group());
                } finally {
                    task.destroy(conn);
                }
                System.out.println("  imported as " + importedVm.getNameLabel(conn));

                // The import brought its own disks along; destroy those too, not just the VM record.
                destroyVmAndDisks(conn, importedVm);
                System.out.println("OK: export-import-vm");
            } finally {
                // Always clean up the file, on failure too: a real export is gigabytes, not worth
                // leaving behind in %TEMP%.
                file.delete();
            }
        } finally {
            Session.logout(conn);
        }
    }

    /**
     * The names of a tar archive's entries.
     *
     * <p>Read with the format's own layout rather than a library: the name is the first 100 bytes of each
     * 512-byte header, the size is octal at offset 124, and every file is padded up to the next 512-byte
     * boundary. Small enough to do here, and it keeps the example free of another dependency.
     */
    private static java.util.List<String> tarNames(java.io.File file) throws Exception {
        java.util.List<String> names = new java.util.ArrayList<>();
        try (java.io.DataInputStream in = new java.io.DataInputStream(
                new java.io.BufferedInputStream(new java.io.FileInputStream(file)))) {
            byte[] header = new byte[512];
            while (in.read(header) == 512) {
                String name = new String(header, 0, 100, java.nio.charset.StandardCharsets.US_ASCII)
                    .trim().replace("\0", "");
                if (name.isEmpty()) break;                      // the end-of-archive marker
                names.add(name);
                String octal = new String(header, 124, 12, java.nio.charset.StandardCharsets.US_ASCII)
                    .trim().replace("\0", "");
                long size = octal.isEmpty() ? 0 : Long.parseLong(octal, 8);
                in.skipBytes((int) ((size + 511) / 512 * 512));
            }
        }
        return names;
    }
}
```

<details><summary>Example output</summary>

```text
Exporting db-01
  wrote 4.0 MiB to sdk-example-export3789225758936647222.xva
  archive holds ova.xml and 4 disk block(s)
  imported as db-01 (imported)
OK: export-import-vm
```

</details>
