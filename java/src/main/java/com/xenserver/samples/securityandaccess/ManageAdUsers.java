package com.xenserver.samples.securityandaccess;

import com.xensource.xenapi.Auth;
import com.xensource.xenapi.Connection;
import com.xensource.xenapi.Host;
import com.xensource.xenapi.Pool;
import com.xensource.xenapi.Role;
import com.xensource.xenapi.Session;
import com.xensource.xenapi.Subject;

import static com.xenserver.samples.PoolConnection.connect;

public final class ManageAdUsers {
    private ManageAdUsers() {
    }

    /**
     * Manage Active Directory users.
     *
     * <p>Join the pool to an Active Directory domain, grant an AD user access with an RBAC role, read it
     * back, then tidy up.
     *
     * <p>Join AD, add a user as a subject with an RBAC role, read it back, then tidy up.
     *
     * <p>Needs a real, reachable AD domain controller - enableExternalAuth fails at the very first call
     * (DNS/LDAP/Kerberos) without one, so domain/adminUser/adminPassword have to identify a real domain to
     * join. Before joining, every host must resolve the domain (point its DNS at a domain controller) and
     * keep its clock close to the DC's (Kerberos). Current Windows DCs want LDAPS (ldaps="true"), which
     * also needs the pool to trust the DC's CA certificate (pool.installTrustedCertificate with purpose
     * "ldaps"). newUser is the account to grant a role to; its subject identity is looked up against the
     * directory, so it has to be a real account there too. A pool already joined to this domain is used as
     * it is - and left joined. The defaults are placeholders: pass your own domain, administrator account
     * and user.
     *
     * <p>Run it:
     *
     * <pre>{@code
     * ManageAdUsers.run("https://xenserver", "root", password, "", "alice", "Password1", "alice", "false");
     * }</pre>
     */
    public static void run(String url, String user, String password, String domain,
            String adminUser, String adminPassword, String newUser, String ldaps) throws Exception {
        Connection conn = connect(url, user, password);
        try {
            Pool pool = Pool.getAll(conn).iterator().next();
            Host coordinator = pool.getMaster(conn);
            boolean alreadyJoined = !domain.isEmpty()
                    && "AD".equals(coordinator.getExternalAuthType(conn))
                    && coordinator.getExternalAuthServiceName(conn).equalsIgnoreCase(domain);
            if (alreadyJoined) {
                System.out.println("Already joined to domain: " + domain);
            } else {
                java.util.Map<String, String> config = new java.util.HashMap<>();
                config.put("user", adminUser);
                config.put("pass", adminPassword);
                config.put("ldaps", ldaps);
                pool.enableExternalAuth(conn, config, domain, "AD");
                System.out.println("Joined domain: " + (!domain.isEmpty() ? domain : "(none given)"));
            }

            String subjectName = !domain.isEmpty() ? newUser + "@" + domain : newUser;
            String sid = Auth.getSubjectIdentifier(conn, subjectName);
            java.util.Map<String, String> info = Auth.getSubjectInformationFromIdentifier(conn, sid);
            // otherConfig/roles are accepted here but discarded by real xapi (it re-derives otherConfig
            // from AD itself, and roles isn't a settable constructor field) - subject.addToRoles below is
            // the call that actually matters.
            Subject.Record srec = new Subject.Record();
            srec.subjectIdentifier = sid;
            srec.otherConfig = new java.util.HashMap<>();
            Subject subject = Subject.create(conn, srec);

            // Resolve the "pool-admin" role with role.getByNameLabel (simpler/more idiomatic than
            // filtering getAllRecords, matches what `xe subject-role-add role-name=` does server-side).
            Role admin = Role.getByNameLabel(conn, "pool-admin").iterator().next();
            subject.addToRoles(conn, admin);
            StringBuilder roles = new StringBuilder();
            for (Role r : subject.getRoles(conn)) roles.append(r.getNameLabel(conn)).append(" ");
            System.out.println("Added subject " + info.get("subject-displayname") + " (" + info.get("subject-name")
                    + ") as " + roles.toString().trim());

            // Revoking access does not end sessions the user already has: logging the subject out is a
            // separate act, and the one that actually gets them off the pool now rather than at next login.
            System.out.println("Logged-in subjects: " + Session.getAllSubjectIdentifiers(conn).size());
            Session.logoutSubjectIdentifier(conn, sid);
            System.out.println("  logged out " + info.get("subject-name"));

            subject.removeFromRoles(conn, admin);
            subject.destroy(conn);
            if (!alreadyJoined) {
                // Leave the way it was found. Passing the admin credentials also removes the pool's
                // computer accounts from the directory; with {} they stay behind in AD.
                java.util.Map<String, String> leaveConfig = new java.util.HashMap<>();
                leaveConfig.put("user", adminUser);
                leaveConfig.put("pass", adminPassword);
                pool.disableExternalAuth(conn, leaveConfig);
            }
            System.out.println("OK: manage-ad-users");
        } finally {
            Session.logout(conn);
        }
    }
}
