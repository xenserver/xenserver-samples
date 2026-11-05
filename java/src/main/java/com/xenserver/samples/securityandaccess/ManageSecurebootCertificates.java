package com.xenserver.samples.securityandaccess;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.Pool;
import com.xensource.xenapi.Session;
import com.xensource.xenapi.Types;
import com.xensource.xenapi.VM;

import java.util.Map;

import static com.xenserver.samples.PoolConnection.connect;

public final class ManageSecurebootCertificates {
    private ManageSecurebootCertificates() {
    }

    /**
     * Manage Secure Boot certificates.
     *
     * <p>Check whether the pool can supply UEFI Secure Boot certificates and whether a guest is ready to
     * use them, then flag a guest whose certificates have gone stale for a refresh at its next boot — and
     * unflag it again.
     *
     * <p>Caution: updating a guest's certificates changes its TPM PCR7 measurements, which can trigger
     * BitLocker recovery on a Windows guest at its next boot. Keep BitLocker recovery keys to hand,
     * suspend BitLocker on affected VMs first, and do the refresh in a monitored maintenance window.
     *
     * <p>Run it:
     *
     * <pre>{@code
     * ManageSecurebootCertificates.run("https://xenserver", "root", password);
     * }</pre>
     */
    public static void run(String url, String user, String password) throws Exception {
        Connection conn = connect(url, user, password);
        try {
            Pool pool = Pool.getAll(conn).iterator().next();

            // A Secure Boot guest carries its own copy of the pool's UEFI certificates, taken when it
            // was created. Rotating the pool's leaves the guest's stale, and the fix is applied at the
            // guest's next boot rather than underneath a running VM - so you flag it and reboot when
            // convenient.
            //
            // First, whether the pool holds the certificates to hand out at all. "ready_no_dbx" means it
            // has the essentials but no revocation list - usable, and not the same answer as "ready".
            System.out.println("Pool Secure Boot readiness: " + pool.getGuestSecurebootReadiness(conn));
            System.out.println("  pool holds certificates:  "
                + !pool.getUefiCertificates(conn).isEmpty());

            // A guest whose certificates have gone stale. Its state is what a client gates the
            // flag/unflag actions on, so it is the field to watch.
            VM vm = null;
            String name = null;
            for (Map.Entry<VM, VM.Record> e : VM.getAllRecords(conn).entrySet()) {
                VM.Record r = e.getValue();
                if (!r.isATemplate && !r.isControlDomain && !r.isASnapshot
                        && r.securebootCertificatesState == Types.VmSecurebootCertificatesState.UPDATE_AVAILABLE) {
                    vm = e.getKey(); name = r.nameLabel; break;
                }
            }
            if (vm == null) {
                // The precondition is the part worth being honest about: this needs a VM whose Secure
                // Boot certificates are already due to refresh. That's a deliberately-provisioned state,
                // not one a normally-provisioned Secure Boot guest is ever in - so report and stop cleanly
                // rather than failing with a bare lookup error.
                System.out.println("No guest needs a Secure Boot certificate refresh right now.");
                System.out.println("OK: manage-secureboot-certificates");
                return;
            }
            System.out.printf("%s: readiness %s, certificates %s%n", name,
                vm.getSecurebootReadiness(conn), vm.getSecurebootCertificatesState(conn));

            // Flagging and unflagging are the same call with opposite booleans.
            vm.updateSecurebootCertificatesOnBoot(conn, true);
            System.out.println("  flagged for refresh:      " + vm.getSecurebootCertificatesState(conn));

            vm.updateSecurebootCertificatesOnBoot(conn, false);
            System.out.println("  unflagged:                " + vm.getSecurebootCertificatesState(conn));

            System.out.println("OK: manage-secureboot-certificates");
        } finally {
            Session.logout(conn);
        }
    }
}
