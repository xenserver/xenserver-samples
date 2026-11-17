<!-- Generated from workflows.json, the example sources and a run of each example. Edit those, not this file. -->

# Snapshot & revert

Take a snapshot of a VM and then revert the VM back to that point-in-time, as you would before a risky change.

Workflow `snapshot-revert`. [All workflows](README.md) · [Connecting](connecting.md)

## PowerShell

Source: [`powershell/VirtualMachines/Invoke-SnapshotRevert.ps1`](../../powershell/VirtualMachines/Invoke-SnapshotRevert.ps1)

```powershell
function Invoke-SnapshotRevert {
    <#
    .SYNOPSIS
        Snapshot & revert.
    .DESCRIPTION
        Take a snapshot of a VM and then revert the VM back to that point-in-time, as you would before a
        risky change.
    .EXAMPLE
        Invoke-SnapshotRevert -Url https://xenserver -UserName root -Password $password -VmName 'web-01'
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password,
        [Parameter(Mandatory = $true)][string]$VmName,
        [string]$SnapshotName = "sdk-example-snapshot"
    )
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password
    $vm = Get-XenVM -Name $VmName |
        Where-Object { -not $_.is_a_template -and -not $_.is_control_domain -and -not $_.is_a_snapshot } |
        Select-Object -First 1
    if (-not $vm) { throw "No VM named '$VmName' was found." }
    Write-Host "Snapshotting VM: $($vm.name_label)"
    $wasRunning = (Get-XenVM -Ref $vm).power_state -eq 'Running'

    $snap = $vm | Invoke-XenVM -XenAction Snapshot -NewName $SnapshotName -PassThru
    Write-Host "Created snapshot: $($snap.uuid)"

    # A client shows a thumbnail of what was on screen when the snapshot was taken, captured from the
    # VM's console at that moment. It is an HTTP transfer alongside the API, not an API call, so the
    # session id travels in the query string. ref names the VM's VNC (rfb) console (the VM itself
    # works too). Only a running VM has a console to capture, and a host that can't reach it answers
    # 404 or 500 instead of an image: the picture is incidental, so carry on. Still pure PowerShell:
    # Connect-Example has already trusted the server's certificate.
    if ((Get-XenVM -Ref $vm).power_state -eq 'Running') {
        $console = (Get-XenVM -Ref $vm).consoles |
            ForEach-Object { Get-XenConsole -Ref $_ } | Where-Object { $_.protocol -eq 'rfb' } |
            Select-Object -First 1
        # An HTTP error status throws in both Windows PowerShell 5.1 and PowerShell 7, with the response
        # (and its status code) on the exception. Bound the whole request: a host's 404 here can leave
        # the connection open, and PowerShell 7 then waits for the end of the error body indefinitely -
        # its -TimeoutSec bounds only connecting, -OperationTimeoutSeconds the rest; 5.1's -TimeoutSec
        # covers both. A picture isn't worth stalling the workflow for.
        $wait = if ($PSVersionTable.PSEdition -eq 'Core') { @{ OperationTimeoutSeconds = 30 } } else { @{ TimeoutSec = 30 } }
        try {
            $thumb = Invoke-WebRequest -UseBasicParsing @wait `
                -Uri "$Url/vncsnapshot?session_id=$($session.opaque_ref)&ref=$($console.opaque_ref)"
            Write-Host "Thumbnail:      $($thumb.RawContentLength) bytes of PNG"
        }
        catch {
            $reason = if ($_.Exception.Response) { "the host answered HTTP $([int]$_.Exception.Response.StatusCode)" }
                      else { "no answer: $($_.Exception.Message)" }
            Write-Host "Thumbnail:      none ($reason)"
        }
    }
    else {
        Write-Host "Thumbnail:      none (the VM is not running, so it has no console)"
    }

    # Revert the VM to the snapshot. The native cmdlet takes the VM (piped in) and the snapshot to
    # restore via -Snapshot. Reverting to a plain snapshot always leaves the VM Halted (xapi hard-shuts-
    # down a running VM before reverting it), even if it was Running a moment ago - restart it
    # afterwards if that's how we found it, so the workflow actually restores what it changed.
    $vm | Invoke-XenVM -XenAction Revert -Snapshot $snap
    Write-Host "Reverted VM to the snapshot."

    if ($wasRunning) {
        $vm | Invoke-XenVM -XenAction Start
        Write-Host "Restarted the VM (it was running before the revert)."
    }

    # A snapshot is itself a (special) VM record, with its own snapshot disks; destroy both to clean up
    # (the source VM's disks are untouched - they are not the snapshot's).
    Remove-VmAndDisks -Ref $snap
    Write-Host "OK: snapshot-revert"
    $session | Disconnect-XenServer
}
```

<details><summary>Example output</summary>

```text
Snapshotting VM: web-01
Created snapshot: 00000001-0000-0000-f709-000000000000
Thumbnail:      23379 bytes of PNG
Reverted VM to the snapshot.
Restarted the VM (it was running before the revert).
OK: snapshot-revert
```

</details>

## xe CLI

Source: [`cli/virtual-machines/snapshot-revert.sh`](../../cli/virtual-machines/snapshot-revert.sh)

```bash
# Snapshot & revert.
#
# Take a snapshot of a VM and then revert the VM back to that point-in-time, as you would before a risky
# change.
#
# Run it:
#   ./workflows.sh snapshot-revert https://xenserver root "$password"

snapshot_revert() {
    vm=$(vm_uuid web-01)
    was_running=$([ "$(xe vm-param-get uuid=$vm param-name=power-state)" = "running" ] && echo true || echo false)
    snap=$(xe vm-snapshot uuid=$vm new-name-label=xe-example-snapshot)
    echo "Created snapshot: $snap"
    xe snapshot-revert snapshot-uuid=$snap
    echo "Reverted to the snapshot."
    # The other languages fetch the snapshot's console thumbnail from GET /vncsnapshot here. `xe` has no
    # command for a plain HTTP transfer that is not vm-export/host-backup, so there is nothing honest to
    # write - the thumbnail is a client-side fetch, not a CLI operation.
    # Reverting to a plain snapshot always leaves the VM Halted (xapi hard-shuts-down a running VM before
    # reverting it), even if it was Running a moment ago - restart it if that's how we found it, so the
    # example actually restores what it changed.
    [ "$was_running" = true ] && xe vm-start uuid=$vm
    # A snapshot owns its own snapshot disks; snapshot-uninstall removes them with it (the VM's disks are
    # untouched - they are not the snapshot's).
    xe snapshot-uninstall snapshot-uuid=$snap force=true
    ok snapshot-revert
}
```

<details><summary>Example output</summary>

```text
Created snapshot: 00000001-0000-0000-f609-000000000000
Reverted to the snapshot.
The following items are about to be destroyed
VM : 00000001-0000-0000-f609-000000000000 (xe-example-snapshot)
VDI: 00000001-0000-0000-f709-000000000000 (web-01 root disk) 
All objects destroyed
OK: snapshot-revert
```

</details>

## Python

Source: [`python/virtual_machines/snapshot_revert.py`](../../python/virtual_machines/snapshot_revert.py)

```python
"""Snapshot & revert.

Take a snapshot of a VM and then revert the VM back to that point-in-time, as you would before a
risky change.

Run it::

    snapshot_revert("https://xenserver", "root", password, "web-01")
"""

import ssl
import urllib.error
import urllib.request

from connection import connect
from helpers import destroy_vm_and_disks, vm_by_name


def snapshot_revert(url, username, password, vm_name, snapshot_name="sdk-example-snapshot"):
    """Snapshot the named VM, then revert the VM back to that snapshot.

    Reverting to a plain snapshot always leaves the VM Halted (xapi hard-shuts-down a running VM
    before reverting it), even if it was Running a moment ago - restart it afterwards if that's
    how we found it, so the workflow actually restores what it changed."""
    session = connect(url, username, password)
    vm_ref = vm_by_name(session, vm_name)
    print("Snapshotting VM: %s" % session.xenapi.VM.get_name_label(vm_ref))
    was_running = session.xenapi.VM.get_power_state(vm_ref) == "Running"

    snap_ref = session.xenapi.VM.snapshot(vm_ref, snapshot_name)
    print("Created snapshot: %s" % session.xenapi.VM.get_uuid(snap_ref))

    # A client shows a thumbnail of what was on screen when the snapshot was taken, captured from the
    # VM's console at that moment. It is an HTTP transfer alongside the API, not an API call, so the
    # session id travels in the query string. ref names the VM's VNC (rfb) console (the VM itself
    # works too). Only a running VM has a console to capture, and a host that can't reach it answers
    # 404 or 500 instead of an image: the picture is incidental, so carry on.
    if session.xenapi.VM.get_power_state(vm_ref) == "Running":
        console = next(c for c in session.xenapi.VM.get_consoles(vm_ref)
                       if session.xenapi.console.get_protocol(c) == "rfb")
        # A host's 404 here can leave the connection open with no end to its body; urlopen raises on the
        # status without reading it, and the timeout bounds any read.
        try:
            with urllib.request.urlopen(
                    "%s/vncsnapshot?session_id=%s&ref=%s" % (url, session._session, console),
                    context=ssl._create_unverified_context(), timeout=30) as response:
                print("Thumbnail:      %d bytes of PNG" % len(response.read()))
        except urllib.error.HTTPError as e:
            print("Thumbnail:      none (the host answered HTTP %d)" % e.code)
        except (urllib.error.URLError, OSError) as e:
            print("Thumbnail:      none (no answer: %s)" % e)
    else:
        print("Thumbnail:      none (the VM is not running, so it has no console)")

    session.xenapi.VM.revert(snap_ref)
    print("Reverted VM to the snapshot.")

    if was_running:
        session.xenapi.VM.start(vm_ref, False, True)
        print("Restarted the VM (it was running before the revert).")

    # A snapshot is itself a (special) VM record, with its own snapshot disks; destroy both to
    # clean up (the source VM's disks are untouched - they are not the snapshot's).
    destroy_vm_and_disks(session, snap_ref)
    print("OK: snapshot-revert")
    session.xenapi.session.logout()
```

<details><summary>Example output</summary>

```text
Snapshotting VM: web-01
Created snapshot: 00000001-0000-0000-f709-000000000000
Thumbnail:      23379 bytes of PNG
Reverted VM to the snapshot.
Restarted the VM (it was running before the revert).
OK: snapshot-revert
```

</details>

## C# (.NET)

Source: [`csharp/VirtualMachines/SnapshotRevert.cs`](../../csharp/VirtualMachines/SnapshotRevert.cs)

```csharp
/// <summary>
/// Take a snapshot of a VM and then revert the VM back to that point-in-time, as you would before a risky
/// change.
/// </summary>
/// <example>
/// <code>
/// Workflows.SnapshotRevert("https://xenserver", "root", password, "web-01");
/// </code>
/// </example>
public static void SnapshotRevert(string url, string user, string password,
    string vmName, string snapshotName = "sdk-example-snapshot")
{
    var session = Connect(url, user, password);
    var vmRef = VmByName(session, vmName);
    Console.WriteLine($"Snapshotting VM: {VM.get_name_label(session, vmRef)}");
    var wasRunning = VM.get_power_state(session, vmRef) == vm_power_state.Running;

    var snapRef = VM.snapshot(session, vmRef, snapshotName);
    Console.WriteLine($"Created snapshot: {VM.get_uuid(session, snapRef)}");

    // A client shows a thumbnail of what was on screen when the snapshot was taken, captured from the
    // VM's console at that moment. It is an HTTP transfer alongside the API, not an API call, so the
    // session id travels in the query string. ref names the VM's VNC (rfb) console (the VM itself
    // works too). Only a running VM has a console to capture, and a host that can't reach it answers
    // 404 or 500 instead of an image: the picture is incidental, so carry on.
    if (VM.get_power_state(session, vmRef) == vm_power_state.Running)
    {
        var console = VM.get_consoles(session, vmRef)
            .First(c => XenAPI.Console.get_protocol(session, c) == console_protocol.rfb);
        // A host's 404 here can leave the connection open with no end to its body, so read only the status
        // first, the body only for a picture, and bound the wait.
        using var client = InsecureHttpClient();
        client.Timeout = TimeSpan.FromSeconds(30);
        try
        {
            using var response = client.GetAsync(
                $"{url}/vncsnapshot?session_id={session.opaque_ref}&ref={console.opaque_ref}",
                HttpCompletionOption.ResponseHeadersRead).Result;
            Console.WriteLine(response.IsSuccessStatusCode
                ? $"Thumbnail:      {response.Content.ReadAsByteArrayAsync().Result.Length} bytes of PNG"
                : $"Thumbnail:      none (the host answered HTTP {(int)response.StatusCode})");
        }
        catch (AggregateException e) when (e.InnerException is TaskCanceledException or HttpRequestException)
        {
            Console.WriteLine($"Thumbnail:      none (no answer: {e.InnerException.Message})");
        }
    }
    else
    {
        Console.WriteLine("Thumbnail:      none (the VM is not running, so it has no console)");
    }

    // Reverting to a plain snapshot always leaves the VM Halted (xapi hard-shuts-down a running VM
    // before reverting it), even if it was Running a moment ago - restart it afterwards if that's
    // how we found it, so the workflow actually restores what it changed.
    VM.revert(session, snapRef);
    Console.WriteLine("Reverted VM to the snapshot.");

    if (wasRunning)
    {
        VM.start(session, vmRef, false, true);
        Console.WriteLine("Restarted the VM (it was running before the revert).");
    }

    DestroyVmAndDisks(session, snapRef);
    Console.WriteLine("OK: snapshot-revert");
    session.logout();
}
```

<details><summary>Example output</summary>

```text
Snapshotting VM: web-01
Created snapshot: 00000001-0000-0000-f709-000000000000
Thumbnail:      23379 bytes of PNG
Reverted VM to the snapshot.
Restarted the VM (it was running before the revert).
OK: snapshot-revert
```

</details>

## Go

*Not found in `go`.*

<details><summary>Example output</summary>

```text
Snapshotting VM: web-01
Created snapshot: 00000001-0000-0000-f709-000000000000
Thumbnail:      23379 bytes of PNG
Reverted VM to the snapshot.
Restarted the VM (it was running before the revert).
OK: snapshot-revert
```

</details>

## Java

Source: [`java/src/main/java/com/xenserver/samples/virtualmachines/SnapshotRevert.java`](../../java/src/main/java/com/xenserver/samples/virtualmachines/SnapshotRevert.java)

```java
package com.xenserver.samples.virtualmachines;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.Session;
import com.xensource.xenapi.Types;
import com.xensource.xenapi.VM;

import org.apache.hc.client5.http.classic.methods.HttpGet;
import org.apache.hc.client5.http.config.RequestConfig;
import org.apache.hc.client5.http.impl.classic.CloseableHttpClient;
import org.apache.hc.core5.http.ClassicHttpResponse;
import org.apache.hc.core5.http.io.entity.EntityUtils;
import org.apache.hc.core5.util.Timeout;

import static com.xenserver.samples.Helpers.destroyVmAndDisks;
import static com.xenserver.samples.Helpers.vmByName;
import static com.xenserver.samples.PoolConnection.connect;
import static com.xenserver.samples.PoolConnection.trustingHttpClient;

public final class SnapshotRevert {
    private SnapshotRevert() {
    }

    /**
     * Snapshot &amp; revert.
     *
     * <p>Take a snapshot of a VM and then revert the VM back to that point-in-time, as you would before a
     * risky change.
     *
     * <p>Run it:
     *
     * <pre>{@code
     * SnapshotRevert.run("https://xenserver", "root", password, "web-01", "sdk-example-snapshot");
     * }</pre>
     */
    public static void run(String url, String user, String password,
            String vmName, String snapshotName) throws Exception {
        Connection conn = connect(url, user, password);
        VM vm = vmByName(conn, vmName);
        System.out.println("Snapshotting VM: " + vm.getNameLabel(conn));
        boolean wasRunning = vm.getPowerState(conn) == Types.VmPowerState.RUNNING;

        VM snap = vm.snapshot(conn, snapshotName);
        System.out.println("Created snapshot: " + snap.getUuid(conn));

        // A client shows a thumbnail of what was on screen when the snapshot was taken, captured from the
        // VM's console at that moment. It is an HTTP transfer alongside the API, not an API call, so the
        // session id travels in the query string. ref names the VM's VNC (rfb) console (the VM itself
        // works too). Only a running VM has a console to capture, and a host that can't reach it answers
        // 404 or 500 instead of an image: the picture is incidental, so carry on.
        if (vm.getPowerState(conn) == Types.VmPowerState.RUNNING) {
            com.xensource.xenapi.Console console = null;
            for (com.xensource.xenapi.Console c : vm.getConsoles(conn)) {
                if (c.getProtocol(conn) == Types.ConsoleProtocol.RFB) { console = c; break; }
            }
            HttpGet thumbGet = new HttpGet(url + "/vncsnapshot?session_id=" + conn.getSessionReference()
                    + "&ref=" + console.toWireString());
            // A host's 404 here can leave the connection open with no end to its body: read the body only for
            // a picture (executeOpen, unlike execute with a handler, doesn't drain the rest), and bound the wait.
            thumbGet.setConfig(RequestConfig.custom().setResponseTimeout(Timeout.ofSeconds(30)).build());
            String thumb;
            try (CloseableHttpClient http = trustingHttpClient();
                    ClassicHttpResponse resp = http.executeOpen(null, thumbGet, null)) {
                thumb = resp.getCode() == 200
                        ? EntityUtils.toByteArray(resp.getEntity()).length + " bytes of PNG"
                        : "none (the host answered HTTP " + resp.getCode() + ")";
            } catch (java.io.IOException e) {
                thumb = "none (no answer: " + e.getMessage() + ")";
            }
            System.out.println("Thumbnail:      " + thumb);
        } else {
            System.out.println("Thumbnail:      none (the VM is not running, so it has no console)");
        }

        snap.revert(conn);
        System.out.println("Reverted VM to the snapshot.");

        // Reverting to a plain snapshot always leaves the VM Halted (xapi hard-shuts-down a running VM
        // before reverting it), even if it was Running a moment ago - restart it afterwards if that's how
        // we found it, so the workflow actually restores what it changed.
        if (wasRunning) {
            vm.start(conn, false, true);
            System.out.println("Restarted the VM (it was running before the revert).");
        }

        // A snapshot is itself a (special) VM record, with its own snapshot disks; destroy both to clean up
        // (the source VM's disks are untouched - they are not the snapshot's).
        destroyVmAndDisks(conn, snap);
        System.out.println("OK: snapshot-revert");
        Session.logout(conn);
    }
}
```

<details><summary>Example output</summary>

```text
Snapshotting VM: web-01
Created snapshot: 00000001-0000-0000-f709-000000000000
Thumbnail:      23379 bytes of PNG
Reverted VM to the snapshot.
Restarted the VM (it was running before the revert).
OK: snapshot-revert
```

</details>
