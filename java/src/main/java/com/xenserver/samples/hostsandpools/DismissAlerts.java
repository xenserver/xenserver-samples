package com.xenserver.samples.hostsandpools;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.Message;
import com.xensource.xenapi.Session;

import java.util.Map;

import static com.xenserver.samples.PoolConnection.connect;

public final class DismissAlerts {
    private DismissAlerts() {
    }

    /**
     * Raise and dismiss alerts.
     *
     * <p>List the pool's alerts, then dismiss one — what the Notifications view does.
     */
    public static void run(String url, String user, String password) throws Exception {
        Connection conn = connect(url, user, password);
        Map<Message, Message.Record> messages = Message.getAllRecords(conn);
        System.out.println("Alerts:         " + messages.size());

        if (messages.isEmpty()) {
            System.out.println("No alerts to dismiss.");
        } else {
            Map.Entry<Message, Message.Record> first = messages.entrySet().iterator().next();
            System.out.println("Dismissing:     " + first.getValue().name
                    + " (priority " + first.getValue().priority + ")");
            first.getKey().destroy(conn);
            System.out.println("Alerts left:    " + Message.getAllRecords(conn).size());
        }
        System.out.println("OK: dismiss-alerts");
        Session.logout(conn);
    }
}
