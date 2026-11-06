<!-- Generated from workflows.json, the example sources and a run of each example. Edit those, not this file. -->

# Drive an asynchronous task

Start a long-running operation asynchronously to get a task back immediately, then poll it to completion and read its result — how to drive operations without blocking.

Workflow `wait-for-task`. [All workflows](README.md) · [Connecting](connecting.md)

## PowerShell

Source: [`powershell/GettingStarted/Invoke-WaitForTask.ps1`](../../powershell/GettingStarted/Invoke-WaitForTask.ps1)

```powershell
function Invoke-WaitForTask {
    <#
    .SYNOPSIS
        Drive an asynchronous task.
    .DESCRIPTION
        Start a long-running operation asynchronously to get a task back immediately, then poll it to
        completion and read its result — how to drive operations without blocking.
    .EXAMPLE
        Invoke-WaitForTask -Url https://xenserver -UserName root -Password $password -TemplateName 'Rocky Linux 8'
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password,
        [Parameter(Mandatory = $true)][string]$TemplateName,
        [string]$NewVmName = "sdk-example-asynctask"
    )
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password
    # Every action has an -Async twin that returns a Task ref immediately; here we poll it by hand to
    # read the progress percentage (Wait-XenTask -ShowProgress, as vm-lifecycle uses, does this for you).
    $template = Get-XenVM -Name $TemplateName | Where-Object { $_.is_a_template } | Select-Object -First 1
    if (-not $template) { throw "No template named '$TemplateName' was found." }
    $task = $template | Invoke-XenVM -XenAction Clone -NewName $NewVmName -Async -PassThru
    $taskRef = $task.opaque_ref
    Write-Host "Started task: $((Get-XenTask -Ref $taskRef).uuid)"

    while ((Get-XenTask -Ref $taskRef).status -eq 'Pending') {
        Write-Host "  progress: $([int]((Get-XenTask -Ref $taskRef).progress * 100))%"
        Start-Sleep -Milliseconds 200
    }
    Write-Host "Task status: $((Get-XenTask -Ref $taskRef).status)"

    # The result of an object-creating task is <value>OpaqueRef:...</value>.
    $result = (Get-XenTask -Ref $taskRef).result
    $vmRef = $result.Replace("<value>", "").Replace("</value>", "").Trim()
    Write-Host "Task produced VM: $((Get-XenVM -Ref $vmRef).name_label)"

    # Tidy up.
    Get-XenVM -Ref $vmRef | Remove-XenVM
    Get-XenTask -Ref $taskRef | Remove-XenTask
    Write-Host "OK: wait-for-task"
    $session | Disconnect-XenServer
}
```

<details><summary>Example output</summary>

```text
Started task: 00000001-0000-0000-ec09-000000000000
Task status: success
Task produced VM: sdk-example-asynctask
OK: wait-for-task
```

</details>

## xe CLI

Source: [`cli/getting-started/wait-for-task.sh`](../../cli/getting-started/wait-for-task.sh)

```bash
# Drive an asynchronous task.
#
# Start a long-running operation asynchronously to get a task back immediately, then poll it to completion and
# read its result — how to drive operations without blocking.
#
# Run it:
#   ./workflows.sh wait-for-task https://xenserver root "$password"

wait_for_task() {
    # xe commands run synchronously (the CLI blocks until the operation completes), so there is no task
    # to poll; the API's tasks are listed here for reference.
    echo "Current tasks: $(count_csv "$(xe task-list params=uuid --minimal)")"
    echo "xe waits for each command to finish, so no async polling is needed."
    echo "OK: wait-for-task"
}
```

<details><summary>Example output</summary>

```text
Current tasks: 0
xe waits for each command to finish, so no async polling is needed.
OK: wait-for-task
```

</details>

## Python

Source: [`python/getting_started/wait_for_task.py`](../../python/getting_started/wait_for_task.py)

```python
"""Drive an asynchronous task.

Start a long-running operation asynchronously to get a task back immediately, then poll it to
completion and read its result — how to drive operations without blocking.

Run it::

    wait_for_task("https://xenserver", "root", password, "Rocky Linux 8")
"""

import time

from connection import connect
from helpers import template_by_name


def wait_for_task(url, username, password, template_name, new_vm_name="sdk-example-asynctask"):
    """Every message has an Async.* twin that returns a Task ref immediately; poll it to completion."""
    session = connect(url, username, password)
    task = session.xenapi.Async.VM.clone(template_by_name(session, template_name), new_vm_name)
    print("Started task: %s" % session.xenapi.task.get_uuid(task))

    while session.xenapi.task.get_status(task) == "pending":
        print("  progress: %.0f%%" % (session.xenapi.task.get_progress(task) * 100))
        time.sleep(0.2)
    print("Task status: %s" % session.xenapi.task.get_status(task))

    # The result of an object-creating task is <value>OpaqueRef:...</value>.
    result = session.xenapi.task.get_result(task)
    vm_ref = result.replace("<value>", "").replace("</value>", "").strip()
    print("Task produced VM: %s" % session.xenapi.VM.get_name_label(vm_ref))

    # Tidy up.
    session.xenapi.VM.destroy(vm_ref)
    session.xenapi.task.destroy(task)
    print("OK: wait-for-task")
    session.xenapi.session.logout()
```

<details><summary>Example output</summary>

```text
Started task: 00000001-0000-0000-ed09-000000000000
Task status: success
Task produced VM: sdk-example-asynctask
OK: wait-for-task
```

</details>

## C# (.NET)

Source: [`csharp/GettingStarted/WaitForTask.cs`](../../csharp/GettingStarted/WaitForTask.cs)

```csharp
/// <summary>
/// Start a long-running operation asynchronously to get a task back immediately, then poll it to
/// completion and read its result — how to drive operations without blocking.
/// </summary>
/// <example>
/// <code>
/// Workflows.WaitForTask("https://xenserver", "root", password, "Rocky Linux 8");
/// </code>
/// </example>
public static void WaitForTask(string url, string user, string password,
    string templateName, string newVmName = "sdk-example-asynctask")
{
    var session = Connect(url, user, password);
    // Every message has an Async.* twin that returns a Task ref immediately; poll it to completion.
    var task = VM.async_clone(session, TemplateByName(session, templateName), newVmName).opaque_ref;
    Console.WriteLine($"Started task: {Task.get_uuid(session, task)}");

    while (Task.get_status(session, task) == task_status_type.pending)
    {
        Console.WriteLine($"  progress: {Task.get_progress(session, task):P0}");
        System.Threading.Thread.Sleep(200);
    }
    Console.WriteLine($"Task status: {Task.get_status(session, task)}");

    // The result of an object-creating task is <value>OpaqueRef:...</value>.
    var result = Task.get_result(session, task);
    var vmRef = result.Replace("<value>", "").Replace("</value>", "").Trim();
    Console.WriteLine($"Task produced VM: {VM.get_name_label(session, vmRef)}");

    // Tidy up.
    VM.destroy(session, vmRef);
    Task.destroy(session, task);
    Console.WriteLine("OK: wait-for-task");
    session.logout();
}
```

<details><summary>Example output</summary>

```text
Started task: 00000001-0000-0000-ec09-000000000000
Task status: success
Task produced VM: sdk-example-asynctask
OK: wait-for-task
```

</details>

## Go

Source: [`go/wait_for_task.go`](../../go/wait_for_task.go)

```go
package main

import (
	"fmt"
	"strings"
	"time"

	"go/xenapi"
)

// waitForTask - Drive an asynchronous task.
//
// Start a long-running operation asynchronously to get a task back immediately, then poll it to
// completion and read its result — how to drive operations without blocking.
//
// Run it:
//
//	waitForTask("https://xenserver", "root", password, "Rocky Linux 8", "sdk-example-asynctask")
func waitForTask(url, user, password, templateName, newVMName string) {
	session := connect(url, user, password)
	// Every message has an Async.* twin that returns a Task ref immediately; poll it to completion.
	task, err := xenapi.VM.AsyncClone(session, templateByName(session, templateName), newVMName)
	check(err)
	uuid, _ := xenapi.Task.GetUUID(session, task)
	fmt.Printf("Started task: %s\n", uuid)

	for {
		status, err := xenapi.Task.GetStatus(session, task)
		check(err)
		if status != xenapi.TaskStatusTypePending {
			break
		}
		progress, _ := xenapi.Task.GetProgress(session, task)
		fmt.Printf("  progress: %.0f%%\n", progress*100)
		time.Sleep(200 * time.Millisecond)
	}
	status, _ := xenapi.Task.GetStatus(session, task)
	fmt.Printf("Task status: %s\n", status)

	// The result of an object-creating task is <value>OpaqueRef:...</value>.
	result, err := xenapi.Task.GetResult(session, task)
	check(err)
	result = strings.TrimSpace(strings.ReplaceAll(strings.ReplaceAll(result, "<value>", ""), "</value>", ""))
	vmRef := xenapi.VMRef(result)
	name, _ := xenapi.VM.GetNameLabel(session, vmRef)
	fmt.Printf("Task produced VM: %s\n", name)

	// Tidy up.
	check(xenapi.VM.Destroy(session, vmRef))
	check(xenapi.Task.Destroy(session, task))
	fmt.Println("OK: wait-for-task")
	session.Logout()
}
```

<details><summary>Example output</summary>

```text
Started task: 00000001-0000-0000-ed09-000000000000
Task status: success
Task produced VM: sdk-example-asynctask
OK: wait-for-task
```

</details>

## Java

Source: [`java/src/main/java/com/xenserver/samples/gettingstarted/WaitForTask.java`](../../java/src/main/java/com/xenserver/samples/gettingstarted/WaitForTask.java)

```java
package com.xenserver.samples.gettingstarted;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.Session;
import com.xensource.xenapi.Task;
import com.xensource.xenapi.Types;
import com.xensource.xenapi.VM;

import static com.xenserver.samples.Helpers.templateByName;
import static com.xenserver.samples.PoolConnection.connect;

public final class WaitForTask {
    private WaitForTask() {
    }

    /**
     * Drive an asynchronous task.
     *
     * <p>Start a long-running operation asynchronously to get a task back immediately, then poll it to
     * completion and read its result — how to drive operations without blocking.
     *
     * <p>Run it:
     *
     * <pre>{@code
     * WaitForTask.run("https://xenserver", "root", password, "Rocky Linux 8", "sdk-example-asynctask");
     * }</pre>
     */
    public static void run(String url, String user, String password,
            String templateName, String newVmName) throws Exception {
        Connection conn = connect(url, user, password);
        // Every message has an Async.* twin that returns a Task ref immediately; poll it to completion.
        Task task = templateByName(conn, templateName).createCloneAsync(conn, newVmName);
        System.out.println("Started task: " + task.getUuid(conn));

        while (task.getStatus(conn) == Types.TaskStatusType.PENDING) {
            System.out.println("  progress: " + Math.round(task.getProgress(conn) * 100) + "%");
            Thread.sleep(200);
        }
        System.out.println("Task status: " + task.getStatus(conn));

        // The result of an object-creating task is <value>OpaqueRef:...</value>.
        String result = task.getResult(conn);
        String vmRef = result.replace("<value>", "").replace("</value>", "").trim();
        VM vm = new VM(vmRef);
        System.out.println("Task produced VM: " + vm.getNameLabel(conn));

        // Tidy up.
        vm.destroy(conn);
        task.destroy(conn);
        System.out.println("OK: wait-for-task");
        Session.logout(conn);
    }
}
```

<details><summary>Example output</summary>

```text
Started task: 00000001-0000-0000-ee09-000000000000
Task status: success
Task produced VM: sdk-example-asynctask
OK: wait-for-task
```

</details>
