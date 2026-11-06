package com.xenserver.samples.hostsandpools;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.DriverVariant;
import com.xensource.xenapi.Host;
import com.xensource.xenapi.HostDriver;
import com.xensource.xenapi.Pool;
import com.xensource.xenapi.Session;

import java.util.Map;

import static com.xenserver.samples.PoolConnection.connect;

public final class ManageDriverVariants {
    private ManageDriverVariants() {
    }

    /**
     * Manage device driver variants.
     *
     * <p>Inspect a host's device drivers and choose which variant of one to use, seeing the difference
     * between the variant that is selected and the one currently loaded.
     */
    public static void run(String url, String user, String password) throws Exception {
        Connection conn = connect(url, user, password);
        try {
            // A driver can ship in several variants - a vendor build alongside the one in the
            // distribution, say. One is SELECTED (what the host will load) and one is ACTIVE (what it
            // has loaded); they differ until the host reboots, which is what makes selecting a variant a
            // scheduled change rather than an immediate one.
            Host host = Pool.getAll(conn).iterator().next().getMaster(conn);

            java.util.List<Map.Entry<HostDriver, HostDriver.Record>> drivers = new java.util.ArrayList<>();
            for (Map.Entry<HostDriver, HostDriver.Record> e : HostDriver.getAllRecords(conn).entrySet())
                if (e.getValue().host.equals(host)) drivers.add(e);
            drivers.sort(java.util.Comparator.comparing(e -> e.getValue().name));
            System.out.println(host.getNameLabel(conn) + " has " + drivers.size() + " driver(s)");
            for (Map.Entry<HostDriver, HostDriver.Record> e : drivers.subList(0, Math.min(3, drivers.size()))) {
                HostDriver.Record d = e.getValue();
                System.out.printf("  %-14s %-10s %d variant(s), active=%s%n",
                    d.name, d.type, d.variants.size(), variantName(conn, d.activeVariant));
            }

            // Select a variant explicitly. It becomes the selected one immediately; whether it is also
            // active depends on whether the hardware is present and the driver already loaded.
            // Host_driver.select refuses a variant whose hardware isn't present (HOST_DRIVER_NO_HARDWARE)
            // - and a host lists drivers for plenty of devices it doesn't have - so pick a driver for
            // hardware this host actually has, and one of its variants that is usable.
            HostDriver driverRef = null;
            DriverVariant variant = null;
            outer:
            for (Map.Entry<HostDriver, HostDriver.Record> e : drivers) {
                for (DriverVariant candidate : e.getValue().variants) {
                    if (candidate.getHardwarePresent(conn)) {
                        driverRef = e.getKey();
                        variant = candidate;
                        break outer;
                    }
                }
            }
            if (driverRef == null)
                throw new RuntimeException("no driver on " + host.getNameLabel(conn)
                        + " has a variant for hardware it has");
            driverRef.select(conn, variant);
            HostDriver.Record after = driverRef.getRecord(conn);
            System.out.printf("  %s: selected %s, active %s%n",
                after.name, variantName(conn, after.selectedVariant), variantName(conn, after.activeVariant));

            System.out.println("OK: manage-driver-variants");
        } finally {
            Session.logout(conn);
        }
    }

    /**
     * A driver variant's name, tolerating the null reference an unloaded driver has.
     */
    private static String variantName(Connection conn, DriverVariant variant) throws Exception {
        if (variant == null || variant.toWireString() == null
                || variant.isNull())
            return "(none)";
        return variant.getName(conn);
    }
}
