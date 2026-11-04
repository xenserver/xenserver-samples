package com.xenserver.samples.virtualmachines;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.Host;
import com.xensource.xenapi.Network;
import com.xensource.xenapi.SR;
import com.xensource.xenapi.Session;
import com.xensource.xenapi.Types;
import com.xensource.xenapi.VBD;
import com.xensource.xenapi.VDI;
import com.xensource.xenapi.VIF;
import com.xensource.xenapi.VM;

import java.util.Map;

import static com.xenserver.samples.Helpers.templateByName;
import static com.xenserver.samples.PoolConnection.connect;

public final class NewVmWizard {
    private NewVmWizard() {
    }

    /**
     * Create a VM (full workflow).
     *
     * <p>Create a VM end to end: pick a template, name the VM, choose an installation source and a home
     * server, set CPU &amp; memory, add a disk on a storage repository, attach a network interface and
     * start it — the full sequence, rather than a single clone call.
     *
     * <p>Run it:
     *
     * <pre>{@code
     * NewVmWizard.run("https://xenserver", "root", password, "Rocky Linux 8", "wizard-vm");
     * }</pre>
     */
    public static void run(String url, String user, String password,
            String templateName, String newVmName) throws Exception {
        final long GiB = 1024L * 1024 * 1024, MiB = 1024L * 1024;

        Connection conn = connect(url, user, password);
        // Page 1 - Template.
        VM template = templateByName(conn, templateName);
        System.out.println("Template:      " + template.getNameLabel(conn));

        // Page 2 - Name and description.
        VM vm = template.createClone(conn, newVmName);
        vm.setNameDescription(conn, "Created by the full New VM wizard example");
        vm.setIsATemplate(conn, false);
        System.out.println("Created VM:    " + vm.getUuid(conn));

        // Page 3 - Installation media (a network install repository).
        vm.addToOtherConfig(conn, "install-repository", "http://mirror.example.com/rocky/9/os/x86_64");
        System.out.println("Install media: network repository");

        // Page 4 - Home server (affinity).
        Map.Entry<Host, Host.Record> he = Host.getAllRecords(conn).entrySet().iterator().next();
        vm.setAffinity(conn, he.getKey());
        System.out.println("Home server:   " + he.getValue().nameLabel);

        // Page 5 - CPU & Memory.
        vm.setVCPUsMax(conn, 2L);
        vm.setVCPUsAtStartup(conn, 2L);
        vm.setMemoryLimits(conn, 512 * MiB, 2 * GiB, 2 * GiB, 2 * GiB);
        System.out.println("CPU/memory:    2 vCPUs, 2 GiB");

        // Page 6 - Storage: add a disk on a (non-ISO) SR.
        SR sr = null;
        String srName = null;
        for (Map.Entry<SR, SR.Record> e : SR.getAllRecords(conn).entrySet()) {
            if (!"iso".equals(e.getValue().contentType)
                    && !"iso".equals(e.getValue().type) && !"udev".equals(e.getValue().type)) {
                sr = e.getKey();
                srName = e.getValue().nameLabel;
                break;
            }
        }
        VDI.Record vdiRec = new VDI.Record();
        vdiRec.nameLabel = newVmName + " disk 0";
        vdiRec.nameDescription = "System disk created by the wizard example";
        vdiRec.SR = sr;
        vdiRec.virtualSize = 24 * GiB;
        vdiRec.type = Types.VdiType.SYSTEM;
        vdiRec.sharable = false;
        vdiRec.readOnly = false;
        vdiRec.otherConfig = new java.util.HashMap<>();
        VDI vdi = VDI.create(conn, vdiRec);

        VBD.Record vbdRec = new VBD.Record();
        vbdRec.VM = vm;
        vbdRec.VDI = vdi;
        vbdRec.userdevice = vm.getAllowedVBDDevices(conn).iterator().next();
        vbdRec.bootable = true;
        vbdRec.mode = Types.VbdMode.RW;
        vbdRec.type = Types.VbdType.DISK;
        vbdRec.empty = false;
        vbdRec.otherConfig = new java.util.HashMap<>();
        vbdRec.qosAlgorithmType = "";
        vbdRec.qosAlgorithmParams = new java.util.HashMap<>();
        VBD.create(conn, vbdRec);
        System.out.println("Storage:       24 GiB disk on " + srName);

        // Page 7 - Networking: attach a VIF to a network.
        Map.Entry<Network, Network.Record> ne = Network.getAllRecords(conn).entrySet().iterator().next();
        VIF.Record vifRec = new VIF.Record();
        vifRec.VM = vm;
        vifRec.network = ne.getKey();
        vifRec.device = vm.getAllowedVIFDevices(conn).iterator().next();
        vifRec.MAC = "";
        vifRec.MTU = 1500L;
        vifRec.otherConfig = new java.util.HashMap<>();
        vifRec.qosAlgorithmType = "";
        vifRec.qosAlgorithmParams = new java.util.HashMap<>();
        // Left unset, the binding's Record defaults these two enums to its own UNRECOGNIZED sentinel,
        // which released xapi rejects outright rather than treating as "no IP configured". Say so
        // explicitly.
        vifRec.ipv4ConfigurationMode = Types.VifIpv4ConfigurationMode.NONE;
        vifRec.ipv6ConfigurationMode = Types.VifIpv6ConfigurationMode.NONE;
        VIF.create(conn, vifRec);
        System.out.println("Networking:    NIC on " + ne.getValue().nameLabel);

        // Page 8 - Finish: start the VM.
        vm.start(conn, false, true);

        System.out.println("--- Result ---");
        System.out.println("power state:   " + vm.getPowerState(conn));
        System.out.println("vCPUs:         " + vm.getVCPUsMax(conn));
        System.out.println("disks:         " + vm.getVBDs(conn).size() + ", NICs: " + vm.getVIFs(conn).size());

        // Tidy up so the example is repeatable.
        vm.hardShutdown(conn);
        vm.destroy(conn);
        vdi.destroy(conn);
        System.out.println("Cleaned up the example VM.");

        System.out.println("OK: new-vm-wizard");
        Session.logout(conn);
    }
}
