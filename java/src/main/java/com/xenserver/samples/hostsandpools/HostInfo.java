package com.xenserver.samples.hostsandpools;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.Host;
import com.xensource.xenapi.Session;

import java.util.Map;

import static com.xenserver.samples.PoolConnection.connect;

public final class HostInfo {
    private HostInfo() {
    }

    /**
     * Host information.
     *
     * <p>Read a host's software version, edition and CPU topology (sockets and cores).
     *
     * <p>Run it:
     *
     * <pre>{@code
     * HostInfo.run("https://xenserver", "root", password);
     * }</pre>
     */
    public static void run(String url, String user, String password) throws Exception {
        Connection conn = connect(url, user, password);
        Host.Record host = Host.getAllRecords(conn).values().iterator().next();
        Map<String, String> sw = host.softwareVersion;
        Map<String, String> cpu = host.cpuInfo;
        System.out.println("Host:     " + host.nameLabel);
        System.out.println("Version:  " + (sw.containsKey("product_version") ? sw.get("product_version") : "?"));
        System.out.println("Edition:  " + host.edition);
        System.out.println("CPUs:     " + (cpu.containsKey("cpu_count") ? cpu.get("cpu_count") : "?")
                + " across " + (cpu.containsKey("socket_count") ? cpu.get("socket_count") : "?") + " socket(s)");
        // The physical identity, straight off the host's DMI/SMBIOS tables. The serial number is what
        // you quote to the hardware vendor, so it identifies this machine and not just its model.
        Map<String, String> bios = host.biosStrings;
        System.out.println("Hardware: " + bios.getOrDefault("system-manufacturer", "?")
                + " " + bios.getOrDefault("system-product-name", "?"));
        System.out.println("Serial:   " + bios.getOrDefault("system-serial-number", "?"));
        System.out.println("BIOS:     " + bios.getOrDefault("bios-version", "?"));
        System.out.println("OK: host-info");
        Session.logout(conn);
    }
}
