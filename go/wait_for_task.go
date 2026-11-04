package main

import (
	"fmt"
	"strings"

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
