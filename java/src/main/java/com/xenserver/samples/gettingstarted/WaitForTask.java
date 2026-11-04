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
