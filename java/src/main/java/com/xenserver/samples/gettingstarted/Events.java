package com.xenserver.samples.gettingstarted;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.Event;
import com.xensource.xenapi.EventBatch;
import com.xensource.xenapi.Session;
import com.xensource.xenapi.VM;

import java.util.LinkedHashSet;
import java.util.Set;

import static com.xenserver.samples.Helpers.vmByName;
import static com.xenserver.samples.PoolConnection.connect;

public final class Events {
    private Events() {
    }

    /**
     * Event monitoring.
     *
     * <p>Subscribe to the event stream and observe a change land as an event — the mechanism for keeping a
     * client's view of the pool live.
     *
     * <p>Run it:
     *
     * <pre>{@code
     * Events.run("https://xenserver", "root", password, "web-01");
     * }</pre>
     */
    public static void run(String url, String user, String password, String vmName) throws Exception {
        Connection conn = connect(url, user, password);
        Set<String> classes = new LinkedHashSet<>();
        classes.add("VM");

        EventBatch batch = Event.from(conn, classes, "", 1.0);
        String token = batch.token;
        System.out.println("Established event token after initial snapshot.");

        VM vm = vmByName(conn, vmName);
        String original = vm.getNameDescription(conn);
        vm.setNameDescription(conn, "changed-to-trigger-event");

        batch = Event.from(conn, classes, token, 5.0);
        System.out.println("Received " + batch.events.size() + " event(s) after the change.");
        int shown = 0;
        for (Event.Record ev : batch.events) {
            if (shown++ >= 3) break;
            System.out.println("  - " + ev.operation + " " + ev.clazz);
        }

        vm.setNameDescription(conn, original); // put it back
        System.out.println("OK: events");
        Session.logout(conn);
    }
}
