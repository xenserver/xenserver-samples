package com.xenserver.samples.virtualmachines;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.Host;
import com.xensource.xenapi.Pool;
import com.xensource.xenapi.Session;
import com.xensource.xenapi.VM;

import static com.xenserver.samples.Helpers.copyOfGuest;
import static com.xenserver.samples.Helpers.destroyVmAndDisks;
import static com.xenserver.samples.Helpers.waitForGuestAgent;
import static com.xenserver.samples.PoolConnection.connect;

public final class VmLifecycle {
    private VmLifecycle() {
    }

    /**
     * VM power lifecycle.
     *
     * <p>Drive a VM through its power states — start it, suspend it to memory, resume it and shut it down
     * cleanly. Suspend and clean shutdown need the guest's cooperation, so this works on a throwaway copy
     * of a VM with a guest OS and PV drivers (source_vm), which is deleted again with its disks
     * afterwards.
     *
     * <p>Suspend and clean shutdown need the guest's cooperation (VM_LACKS_FEATURE without PV drivers), so
     * the copy is made from sourceVm, a VM with a guest OS and PV drivers, and the example waits for the
     * guest to report in after starting. Suspend also needs a suspend-image SR (the VM's own, else the
     * pool's, else the host's); check one is actually configured before trying, rather than assuming it
     * is.
     */
    public static void run(String url, String user, String password,
            String sourceVm, String newVmName) throws Exception {
        Connection conn = connect(url, user, password);
        VM vm = copyOfGuest(conn, sourceVm, newVmName);

        System.out.println("Initial power state: " + vm.getPowerState(conn));
        vm.start(conn, false, true);
        waitForGuestAgent(conn, vm);
        System.out.println("After start:   " + vm.getPowerState(conn));

        // The emulated hardware (the device model) can be restarted under a running guest without
        // rebooting it - what you reach for when the VM's virtual devices misbehave.
        vm.restartDeviceModels(conn);
        System.out.println("Device models restarted; still " + vm.getPowerState(conn));

        if (hasSuspendSr(conn, vm)) {
            vm.suspend(conn);
            System.out.println("After suspend: " + vm.getPowerState(conn));
            vm.resume(conn, false, true);
            waitForGuestAgent(conn, vm);   // the PV drivers reconnect after a resume
            System.out.println("After resume:  " + vm.getPowerState(conn));
        } else {
            System.out.println("Skipping suspend/resume: no suspend-image SR is configured for this VM/pool/host");
        }

        // A clean shutdown asks the guest OS to shut itself down, as pressing the power button would.
        vm.cleanShutdown(conn);
        System.out.println("After shutdown:" + vm.getPowerState(conn));

        destroyVmAndDisks(conn, vm);
        System.out.println("OK: vm-lifecycle");
        Session.logout(conn);
    }

    /**
     * Whether VM.suspend has a suspend-image SR to use: the VM's own, else the pool's, else the resident
     * host's - the same fallback order xapi's choose_suspend_sr uses.
     */
    private static boolean hasSuspendSr(Connection conn, VM vm) throws Exception {
        if (!vm.getSuspendSR(conn).isNull()) return true;
        Pool pool = Pool.getAll(conn).iterator().next();
        if (!pool.getSuspendImageSR(conn).isNull()) return true;
        Host host = pool.getMaster(conn);
        return !host.getSuspendImageSr(conn).isNull();
    }
}
