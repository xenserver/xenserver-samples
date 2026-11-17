package com.xenserver.samples.virtualmachines;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.Session;
import com.xensource.xenapi.Types;
import com.xensource.xenapi.VM;

import static com.xenserver.samples.Helpers.destroyVmAndDisks;
import static com.xenserver.samples.Helpers.vmByName;
import static com.xenserver.samples.Helpers.waitForGuestAgent;
import static com.xenserver.samples.PoolConnection.connect;

public final class CheckpointVm {
    private CheckpointVm() {
    }

    /**
     * Checkpoint &amp; revert.
     *
     * <p>Take a checkpoint of a running VM (disk AND memory, unlike a plain snapshot) and revert to it, as
     * you would before a risky in-guest change. A checkpoint needs the guest's cooperation, so the VM must
     * have a guest OS with PV drivers (vm_name).
     *
     * <p>Checkpointing needs the guest's cooperation (VM_LACKS_FEATURE without PV drivers): the guest
     * freezes its processes and suspends itself. A guest that is still booting can fail to freeze a process
     * that is busy starting up, and it then abandons the suspend without telling the host, which waits until
     * VM_SUSPEND_TIMEOUT - so checkpoint a VM that has finished booting, as here.
     *
     * <p>Run it:
     *
     * <pre>{@code
     * CheckpointVm.run("https://xenserver", "root", password, "web-01");
     * }</pre>
     */
    public static void run(String url, String user, String password, String vmName) throws Exception {
        Connection conn = connect(url, user, password);
        // A checkpoint captures disk AND memory (unlike a plain snapshot), so the VM must be running.
        VM vm = vmByName(conn, vmName);
        if (vm.getPowerState(conn) != Types.VmPowerState.RUNNING) {
            throw new IllegalStateException(vmName + " must be running to be checkpointed");
        }
        // Running is not enough: the VM may have just been started (or restarted, as snapshot-revert does),
        // so wait for its guest to finish booting first.
        waitForGuestAgent(conn, vm);

        VM checkpoint = vm.checkpoint(conn, "sdk-example-checkpoint-1");
        System.out.println("Created checkpoint: " + checkpoint.getUuid(conn));
        System.out.println("is_a_snapshot = " + checkpoint.getIsASnapshot(conn));

        checkpoint.revert(conn);
        // A checkpoint's own power_state is always Suspended (it captures memory as well as disk), and
        // revert restores exactly that - so the VM is Suspended here, not Running as it was before the
        // checkpoint, with a suspend_VDI holding the checkpoint's memory image. VM.resume picks up from
        // there (and frees that memory image).
        System.out.println("Reverted " + vmName + " to the checkpoint; power state now: " + vm.getPowerState(conn));
        vm.resume(conn, false, true);
        System.out.println("Resumed " + vmName + "; power state now: " + vm.getPowerState(conn));

        // Tidy up. The checkpoint owns its own snapshot disks, separate from the VM's.
        destroyVmAndDisks(conn, checkpoint);
        System.out.println("Deleted the checkpoint.");
        System.out.println("OK: checkpoint-vm");
        Session.logout(conn);
    }
}
