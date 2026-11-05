package com.xenserver.samples.virtualmachines;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.GPUGroup;
import com.xensource.xenapi.Host;
import com.xensource.xenapi.Network;
import com.xensource.xenapi.PIF;
import com.xensource.xenapi.Pool;
import com.xensource.xenapi.SR;
import com.xensource.xenapi.Session;
import com.xensource.xenapi.Types;
import com.xensource.xenapi.VBD;
import com.xensource.xenapi.VDI;
import com.xensource.xenapi.VGPU;
import com.xensource.xenapi.VIF;
import com.xensource.xenapi.VM;

import java.util.HashMap;
import java.util.Map;

import static com.xenserver.samples.Helpers.destroyVmAndDisks;
import static com.xenserver.samples.Helpers.vmByName;
import static com.xenserver.samples.PoolConnection.connect;

public final class CrossPoolCopyVm {
    private CrossPoolCopyVm() {
    }

    /**
     * Cross-pool copy a VM.
     *
     * <p>Copy a VM from one pool to another: open a session to each pool, obtain a receiver token on the
     * destination, then send a copy of the VM from the source. Takes the destination pool's URL as an
     * extra argument after the password.
     *
     * <p>Copy a VM from one pool to another (Storage XenMotion copy): get a receiver token from the
     * destination with host.migrate_receive, then VM.migrate_send with copy=true on the source.
     *
     * <p>Run it:
     *
     * <pre>{@code
     * CrossPoolCopyVm.run("https://poolA", "root", password, "https://poolB", "db-01", null, null, null);
     * }</pre>
     */
    public static void run(String url, String user, String password, String destUrl,
            String vmName, String destUser, String destPassword) throws Exception {
        run(url, user, password, destUrl, vmName, destUser, destPassword, null);
    }

    /**
     * As {@link #run(String, String, String, String, String, String, String)}, but carrying the
     * migration traffic over the named destination network instead of its management network.
     */
    public static void run(String url, String user, String password, String destUrl,
            String vmName, String destUser, String destPassword, String transferNetwork) throws Exception {
        Connection source = connect(url, user, password);
        Connection dest = connect(destUrl, destUser != null ? destUser : user,
                destPassword != null ? destPassword : password);
        // Destination: choose a host, network and SR, then ask for a receiver token. The disks go to
        // the destination pool's default SR.
        Pool destPool = Pool.getAll(dest).iterator().next();
        Host destHost = destPool.getMaster(dest);
        SR destSr = destPool.getDefaultSR(dest);
        Network destManagementNetwork = null;
        for (PIF pif : destHost.getPIFs(dest))
            if (pif.getManagement(dest)) destManagementNetwork = pif.getNetwork(dest);
        Network migrationNetwork;
        if (transferNetwork != null) {
            migrationNetwork = null;
            for (Network net : Network.getAll(dest))
                if (net.getNameLabel(dest).equals(transferNetwork)) migrationNetwork = net;
        } else {
            // For performance, production use should carry migration traffic over a dedicated network
            // rather than the management network - pass transferNetwork with the name of one.
            migrationNetwork = destManagementNetwork;
        }
        Map<String, String> receiver = destHost.migrateReceive(dest, migrationNetwork, new HashMap<>());

        // Source: map every disk to the destination SR and every NIC to the destination pool's
        // management network (the VM's guest-visible NICs, independent of the migration transfer),
        // then send with copy=true (the source VM is left intact).
        VM vm = vmByName(source, vmName);
        Map<VDI, SR> vdiMap = new HashMap<>();
        for (VBD vbd : vm.getVBDs(source))
            if (vbd.getType(source) == Types.VbdType.DISK) vdiMap.put(vbd.getVDI(source), destSr);
        Map<VIF, Network> vifMap = new HashMap<>();
        for (VIF vif : vm.getVIFs(source)) vifMap.put(vif, destManagementNetwork);

        Map<String, String> options = new HashMap<>();
        options.put("copy", "true");
        VM copy = vm.migrateSend(source, receiver, false, vdiMap, vifMap, options,
                new HashMap<VGPU, GPUGroup>());
        System.out.println("Sent '" + vmName + "' to the destination pool (copy); source still present: "
                + vmByName(source, vmName).equals(vm));
        // The result is the new VM's ref on the DESTINATION pool - use the destination session to read it.
        System.out.println("  the copy on the destination: " + copy.getNameLabel(dest) + " ("
                + copy.getUuid(dest) + ")");

        // Tidy up so the example is repeatable: the copy and its disks, on the destination pool.
        destroyVmAndDisks(dest, copy);
        System.out.println("OK: cross-pool-copy-vm");
        Session.logout(source);
        Session.logout(dest);
    }
}
