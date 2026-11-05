package com.xenserver.samples.virtualmachines;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.GPUGroup;
import com.xensource.xenapi.Session;
import com.xensource.xenapi.VGPU;
import com.xensource.xenapi.VGPUType;
import com.xensource.xenapi.VM;

import java.util.HashMap;
import java.util.Map;
import java.util.Set;

import static com.xenserver.samples.Helpers.destroyVmAndDisks;
import static com.xenserver.samples.Helpers.provision;
import static com.xenserver.samples.Helpers.templateByName;
import static com.xenserver.samples.PoolConnection.connect;

public final class CreateVmWithVgpu {
    private CreateVmWithVgpu() {
    }

    /**
     * Create a VM with a vGPU.
     *
     * <p>Provision a VM from a template and assign it a virtual GPU: find a GPU group that offers a vGPU
     * type, attach it, and read the assignment back.
     *
     * <p>Run it:
     *
     * <pre>{@code
     * CreateVmWithVgpu.run("https://xenserver", "root", password, "Rocky Linux 8", "sdk-example-vgpu-vm");
     * }</pre>
     */
    public static void run(String url, String user, String password,
            String templateName, String newVmName) throws Exception {
        Connection conn = connect(url, user, password);
        // Find a GPU group that offers a real (non-passthrough) vGPU type, plus that type.
        GPUGroup group = null;
        VGPUType vgpuType = null;
        outer:
        for (Map.Entry<GPUGroup, GPUGroup.Record> e : GPUGroup.getAllRecords(conn).entrySet()) {
            if (e.getValue().PGPUs.isEmpty()) continue;
            for (VGPUType t : e.getValue().supportedVGPUTypes) {
                if (!"passthrough".equals(t.getModelName(conn))) {
                    group = e.getKey();
                    vgpuType = t;
                    break outer;
                }
            }
        }
        if (group == null) throw new RuntimeException("no GPU group offers a vGPU type");
        System.out.println("Using vGPU type: " + vgpuType.getModelName(conn)
                + " (" + vgpuType.getFramebufferSize(conn) / (1024 * 1024) + " MB framebuffer)");

        // Provision a fresh VM from the template to attach the vGPU to.
        VM vm = templateByName(conn, templateName).createClone(conn, newVmName);
        provision(conn, vm);

        // Assign the vGPU: device "0" is the VM's first vGPU slot, other_config is empty.
        VGPU vgpu = VGPU.create(conn, vm, group, "0", new HashMap<String, String>(), vgpuType);
        System.out.println("Created vGPU: " + vgpu.getUuid(conn));

        // Read the assignment back.
        Set<VGPU> vgpus = vm.getVGPUs(conn);
        String assigned = vgpus.iterator().next().getType(conn).getModelName(conn);
        System.out.println("VM now has " + vgpus.size() + " vGPU(s); type = " + assigned);

        // Tidy up so the example is repeatable.
        vgpu.destroy(conn);
        destroyVmAndDisks(conn, vm);
        System.out.println("Cleaned up the example VM and its vGPU.");

        System.out.println("OK: create-vm-with-vgpu");
        Session.logout(conn);
    }
}
