package com.xenserver.samples.gettingstarted;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.Host;
import com.xensource.xenapi.Session;
import com.xensource.xenapi.Types;

import static com.xenserver.samples.PoolConnection.connect;

public final class ErrorHandling {
    private ErrorHandling() {
    }

    /**
     * Handle an API error.
     *
     * <p>Catch an API failure and inspect its error code and parameters — the shape of every error the API
     * returns, and how to react to it robustly.
     *
     * <p>Run it:
     *
     * <pre>{@code
     * ErrorHandling.run("https://xenserver", "root", password);
     * }</pre>
     */
    public static void run(String url, String user, String password) throws Exception {
        Connection conn = connect(url, user, password);
        // XenAPI errors surface as a XenAPIException. Specific errors are typed subclasses (e.g.
        // UuidInvalid): the class name identifies the error. getMessage() is NOT the readable text here:
        // in Java SDKs up to 26.22 the generated XenAPIException never calls super(message), so
        // Throwable.getMessage() is null for every typed XenAPI exception. shortDescription and
        // errorDescription carry the real text, and work with every SDK version.
        try {
            Host.getByUuid(conn, "this-uuid-does-not-exist");
            System.out.println("unexpected: no error");
        } catch (Types.XenAPIException e) {
            System.out.println("Caught expected failure: " + e.getClass().getSimpleName());
            System.out.println("Short message: " + e.shortDescription);
            if (e.errorDescription != null)
                System.out.println("Error fields: " + java.util.Arrays.toString(e.errorDescription));
        }
        System.out.println("OK: error-handling");
        Session.logout(conn);
    }
}
