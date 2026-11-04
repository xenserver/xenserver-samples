package com.xenserver.samples.hostsandpools;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.Host;
import com.xensource.xenapi.Pool;
import com.xensource.xenapi.Session;
import com.xensource.xenapi.Types;
import com.xensource.xenapi.VM;

import java.util.HashMap;
import java.util.Map;
import java.util.Set;
import java.util.TreeMap;

import static com.xenserver.samples.PoolConnection.connect;

public final class WlbRecommendations {
    private WlbRecommendations() {
    }

    /**
     * Read workload-balancing recommendations.
     *
     * <p>Point the pool at a workload-balancing appliance, read its placement recommendations for the pool
     * and for one VM, then disconnect it.
     *
     * <p>Connect a workload-balancing appliance and read its placement advice.
     *
     * <p>Needs a real, reachable WLB appliance: pool.initializeWlb makes a synchronous HTTP call to it and
     * raises WLB_CONNECTION_REFUSED/WLB_CONNECTION_RESET if it can't connect - there is no way to fake
     * this with a placeholder. wlbHostPort is host:port, with no URL scheme - that is the real wire format
     * (xe pool-initialize-wlb wlb_url="10.x.x.x:30601" ...), not a URL.
     *
     * <p>The pool checks the appliance's TLS certificate (pool.wlb_verify_cert), and only against the
     * certificates installed with Pool.certificateInstall - not install_trusted_certificate's. A fresh
     * appliance has a self-signed one, so pass it as wlbCertificate (a PEM file): without it initializeWlb
     * fails with INTERNAL_ERROR "Connection failed: configuration failed." and no hint that the
     * certificate is the reason.
     *
     * <p>Run it:
     *
     * <pre>{@code
     * WlbRecommendations.run("https://xenserver", "root", password, "web-01");
     * }</pre>
     */
    public static void run(String url, String user, String password, String vmName,
            String wlbHostPort, String wlbUsername, String wlbPassword, String wlbCertificate) throws Exception {
        Connection conn = connect(url, user, password);
        try {
            String certName = "";
            if (!wlbCertificate.isEmpty()) {
                certName = "sdk-example-wlb.pem";
                String cert = java.nio.file.Files.readString(java.nio.file.Path.of(wlbCertificate));
                Pool.certificateInstall(conn, certName, cert); // a pool-wide call: no pool argument
            }
            Pool.initializeWlb(conn, wlbHostPort, wlbUsername, wlbPassword, user, password);
            try {
                // Initializing connects the pool to the appliance but leaves balancing off: every WLB
                // call after this would fail WLB_DISABLED until it's switched on.
                Pool pool = Pool.getAll(conn).iterator().next();
                pool.setWlbEnabled(conn, true);
                System.out.println("WLB: " + pool.getWlbUrl(conn));

                // Other bindings read these BY POSITION -- [0] "wlb", [1] the destination host's UUID,
                // [2] and [3] ids, [4] the reason -- but Java CANNOT, and this is the one example where
                // the binding's type matters more than the API's.
                //
                // The datamodel declares the value as `Set String`, so this binding hands back a real
                // java.util.Set. Two things follow, and neither is visible from C#, whose binding uses
                // String[]: equal elements collapse, and iteration order is not the wire order. Indexing
                // a copy of the set returns whichever element happens to land there -- in testing, index
                // 1 was the reason and index 4 the "wlb" tag. So print the whole recommendation and let
                // a human read it; a program that needs the fields must use an ordered binding or the
                // raw JSON.
                for (Map.Entry<VM, Set<String>> rec : Pool.retrieveWlbRecommendations(conn).entrySet()) {
                    System.out.println("  move " + rec.getKey().getNameLabel(conn)
                            + ": " + String.join(" ", rec.getValue()));
                }

                // Same caveat for a VM's own recommendations, which are keyed by host and rate each as a
                // destination - higher is better (a real appliance rated hosts 6.1 here, so not capped
                // at XenCenter's five stars). Right after connecting, the appliance is still discovering
                // the pool and answers WLB_INTERNAL_ERROR 4024 ("Pool discovery has not been started") -
                // keep asking for a while. The generated binding drops WLB_INTERNAL_ERROR's parameters
                // (its no-arg constructor discards errorDescription), so unlike the other bindings this
                // cannot check for 4024 specifically and retries on any WlbInternalError instead.
                VM vm = VM.getByNameLabel(conn, vmName).iterator().next();
                long deadline = System.currentTimeMillis() + 10 * 60 * 1000;
                Map<Host, Set<String>> vmRecs;
                while (true) {
                    try {
                        vmRecs = vm.retrieveWlbRecommendations(conn);
                        break;
                    } catch (Types.WlbInternalError e) {
                        if (System.currentTimeMillis() > deadline) throw e;
                        Thread.sleep(15000);
                    }
                }
                for (Map.Entry<Host, Set<String>> rec : vmRecs.entrySet()) {
                    System.out.println("  " + rec.getKey().getNameLabel(conn)
                            + ": " + String.join(" ", rec.getValue()));
                }

                // The appliance's own settings are read and written as one flat map of strings. Send a
                // nightly reporting schedule, then read the configuration back to confirm it took.
                Map<String, String> wlbConfig = new HashMap<>();
                wlbConfig.put("ReportingCronString", "0 3 * * *");
                Pool.sendWlbConfiguration(conn, wlbConfig);
                Map<String, String> config = new TreeMap<>(Pool.retrieveWlbConfiguration(conn));
                StringBuilder cfgStr = new StringBuilder();
                for (Map.Entry<String, String> kv : config.entrySet()) {
                    if (cfgStr.length() > 0) cfgStr.append(", ");
                    cfgStr.append(kv.getKey()).append("=").append(kv.getValue());
                }
                System.out.println("  appliance configuration: " + cfgStr);
            } finally {
                // Disconnect from the appliance however the above went, or the pool stays attached to it.
                Pool.deconfigureWlb(conn);
                if (!certName.isEmpty()) Pool.certificateUninstall(conn, certName);
            }
            System.out.println("OK: wlb-recommendations");
        } finally {
            Session.logout(conn);
        }
    }
}
