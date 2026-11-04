package com.xenserver.samples.hostsandpools;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.Pool;
import com.xensource.xenapi.Session;
import com.xensource.xenapi.Types;

import static com.xenserver.samples.PoolConnection.connect;

public final class RotatePoolSecret {
    private RotatePoolSecret() {
    }

    /**
     * Rotate the pool secret.
     *
     * <p>Rotate the shared secret that authenticates pool members to each other.
     *
     * <p>xapi checks its own preconditions before rotating - HA must be disabled, every host must be live,
     * no rolling pool upgrade may be in progress, and the pool must be licensed for it - and raises a
     * clear error naming which one failed rather than silently refusing. Report that explanation instead
     * of letting an unhandled XenAPIException speak for itself. Still reports OK either way - the point is
     * demonstrating the precondition handling, not requiring the rotation to succeed.
     */
    public static void run(String url, String user, String password) throws Exception {
        Connection conn = connect(url, user, password);
        Pool pool = Pool.getAll(conn).iterator().next();
        System.out.println("Pool:           " + pool.getNameLabel(conn));

        try {
            // A pool-wide operation; existing sessions survive it.
            Pool.rotateSecret(conn);
            System.out.println("Rotated. Still connected: " + (Pool.getAll(conn).size() == 1));
        } catch (Types.HaIsEnabled e) {
            System.out.println("Could not rotate the pool secret: HA is enabled on this pool; disable it first.");
        } catch (Types.CannotContactHost e) {
            System.out.println("Could not rotate the pool secret: a host in the pool is not reachable.");
        } catch (Types.NotSupportedDuringUpgrade e) {
            System.out.println("Could not rotate the pool secret: a rolling pool upgrade is in progress.");
        } catch (Types.LicenceRestriction e) {
            System.out.println("Could not rotate the pool secret: this edition is not licensed for pool secret rotation.");
        } catch (Types.XenAPIException e) {
            System.out.println("Could not rotate the pool secret: " + e.shortDescription);
        }
        System.out.println("OK: rotate-pool-secret");
        Session.logout(conn);
    }
}
