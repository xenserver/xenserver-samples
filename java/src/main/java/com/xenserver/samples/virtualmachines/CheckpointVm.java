package com.xenserver.samples.virtualmachines;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.Session;
import com.xensource.xenapi.VM;

import static com.xenserver.samples.Helpers.copyOfGuest;
import static com.xenserver.samples.Helpers.destroyVmAndDisks;
import static com.xenserver.samples.Helpers.waitForGuestAgent;
import static com.xenserver.samples.PoolConnection.connect;

public final class CheckpointVm {
    private CheckpointVm() {
    }

    /**
     * Checkpoint &amp; revert.
     *
     * <p>Take a checkpoint of a running VM (disk AND memory, unlike a plain snapshot) and revert to it, as
     * you would before a risky in-guest change. A checkpoint needs the guest's cooperation, so this works
     * on a throwaway copy of a VM with a guest OS and PV drivers (source_vm).
     *
     * <p>Checkpointing needs the guest's cooperation (VM_LACKS_FEATURE without PV drivers), hence a copy
     * of sourceVm - a VM with a guest OS and PV drivers - rather than an OS-less template clone.
     *
     * <p>Run it:
     *
     * <pre>{@code
     * CheckpointVm.run("https://xenserver", "root", password, "web-01", "sdk-example-checkpoint");
     * }</pre>
     */
    public static void run(String url, String user, String password,
            String sourceVm, String newVmName) throws Exception {
        Connection conn = connect(url, user, password);
        // A checkpoint captures disk AND memory (unlike a plain snapshot), so the VM must be running.
        VM vm = copyOfGuest(conn, sourceVm, newVmName);
        vm.start(conn, false, true);
        waitForGuestAgent(conn, vm);

        VM checkpoint = vm.checkpoint(conn, "sdk-example-checkpoint-1");
        System.out.println("Created checkpoint: " + checkpoint.getUuid(conn));
        System.out.println("is_a_snapshot = " + checkpoint.getIsASnapshot(conn));

        checkpoint.revert(conn);
        // A checkpoint's own power_state is always Suspended (it captures memory as well as disk), and
        // revert restores exactly that - so the VM is Suspended here, not Running as it was before the
        // checkpoint, with a suspend_VDI holding the checkpoint's memory image. VM.resume clears that:
        // destroying a Suspended VM directly (as a bare "if Running: hardShutdown" check would, since the
        // VM is never Running here) leaves that suspend_VDI behind as a storage leak.
        System.out.println("Reverted the VM to the checkpoint; power state now: " + vm.getPowerState(conn));
        vm.resume(conn, false, true);

        // Tidy up. The checkpoint owns its own snapshot disks, separate from the VM's.
        destroyVmAndDisks(conn, checkpoint);
        vm.hardShutdown(conn);
        destroyVmAndDisks(conn, vm);
        System.out.println("OK: checkpoint-vm");
        Session.logout(conn);
    }
}
