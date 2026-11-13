package com.xenserver.samples.virtualmachines;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.PUSB;
import com.xensource.xenapi.Session;
import com.xensource.xenapi.VM;
import com.xensource.xenapi.VUSB;

import java.util.HashMap;
import java.util.Map;

import static com.xenserver.samples.PoolConnection.connect;

public final class AttachUsbDevice {
    private AttachUsbDevice() {
    }

    /**
     * Attach a USB device to a VM.
     *
     * <p>List the USB devices a host exposes, enable passthrough on one, attach it to a VM and detach it
     * again.
     *
     * <p>Run it:
     *
     * <pre>{@code
     * AttachUsbDevice.run("https://xenserver", "root", password, "web-01");
     * }</pre>
     */
    public static void run(String url, String user, String password, String vmName)
            throws Exception {
        Connection conn = connect(url, user, password);
        try {
            VM vm = VM.getByNameLabel(conn, vmName).iterator().next();

            Map.Entry<PUSB, PUSB.Record> entry =
                    PUSB.getAllRecords(conn).entrySet().iterator().next();
            System.out.println("Device:         " + entry.getValue().description);

            // Passthrough is off until an administrator releases the device: attaching one that has
            // not been released fails rather than silently doing nothing.
            entry.getKey().setPassthroughEnabled(conn, true);

            VUSB vusb = VUSB.create(conn, vm, entry.getValue().USBGroup,
                    new HashMap<String, String>());
            System.out.println("Attached:       " + vm.getVUSBs(conn).size() + " device(s)");

            // VUSB.destroy refuses a VUSB that is still attached (OPERATION_NOT_ALLOWED) - on a running VM
            // it gets plugged in as soon as it's created, so unplug it first.
            if (vusb.getCurrentlyAttached(conn)) vusb.unplug(conn);
            vusb.destroy(conn);
            entry.getKey().setPassthroughEnabled(conn, false);
            System.out.println("OK: attach-usb-device");
        } finally {
            Session.logout(conn);
        }
    }
}
