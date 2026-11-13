package com.xenserver.samples.virtualmachines;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.Session;
import com.xensource.xenapi.VM;

import java.util.Map;

import static com.xenserver.samples.Helpers.destroyVmAndDisks;
import static com.xenserver.samples.Helpers.provision;
import static com.xenserver.samples.Helpers.templateByName;
import static com.xenserver.samples.PoolConnection.connect;

public final class VmBootConfig {
    private VmBootConfig() {
    }

    /**
     * VM boot configuration.
     *
     * <p>Set a VM's vCPU counts and boot order, then read them back.
     *
     * <p>Run it:
     *
     * <pre>{@code
     * VmBootConfig.run("https://xenserver", "root", password, "Rocky Linux 8", "sdk-example-boot");
     * }</pre>
     */
    public static void run(String url, String user, String password,
            String templateName, String newVmName) throws Exception {
        Connection conn = connect(url, user, password);
        VM vm = templateByName(conn, templateName).createClone(conn, newVmName);
        provision(conn, vm);

        vm.setVCPUsMax(conn, 4L);
        vm.setVCPUsAtStartup(conn, 2L);

        // Boot mode: firmware ("bios"/"uefi") lives in HVM_boot_params; Secure Boot in
        // platform["secureboot"]. "auto" (not a hard-coded "true") is the xe convention:
        // xapi resolves it against whether the pool actually holds Secure Boot certificates, at VM.start
        // time - a hard "true" would claim Secure Boot is on even on a template that was never set up for
        // it, since setPlatform does no validation of its own.
        Map<String, String> bootParams = new java.util.HashMap<>();
        bootParams.put("order", "cdn");
        bootParams.put("firmware", "uefi");
        vm.setHVMBootParams(conn, bootParams);
        Map<String, String> platform = vm.getPlatform(conn);
        platform.put("secureboot", "auto");
        vm.setPlatform(conn, platform);
        System.out.println("vCPUs: " + vm.getVCPUsAtStartup(conn) + "/" + vm.getVCPUsMax(conn));
        System.out.println("Boot order: " + vm.getHVMBootParams(conn).get("order"));
        System.out.println("Boot mode: firmware=" + vm.getHVMBootParams(conn).get("firmware")
                + ", secureboot=" + vm.getPlatform(conn).get("secureboot")
                + " (resolved against pool certificates at boot)");

        destroyVmAndDisks(conn, vm);
        System.out.println("OK: vm-boot-config");
        Session.logout(conn);
    }
}
