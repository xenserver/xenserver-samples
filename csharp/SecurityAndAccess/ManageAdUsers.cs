using System;
using System.Collections.Generic;
using System.Linq;
using XenAPI;
using Console = System.Console; // XenAPI also defines a Console class

namespace XenServerWorkflows;

internal static partial class Workflows
{
    /// <summary>
    /// Join the pool to an Active Directory domain, grant an AD user access with an RBAC role, read it back,
    /// then tidy up.
    /// </summary>
    /// <example>
    /// <code>
    /// Workflows.ManageAdUsers("https://xenserver", "root", password);
    /// </code>
    /// </example>
    /// <remarks>
    /// Join AD, add a user as a subject with an RBAC role, read it back, then tidy up. Needs a real,
    /// reachable AD domain controller - enable_external_auth fails at the very first call (DNS/LDAP/Kerberos)
    /// without one, so domain/admin_user/admin_password have to identify a real domain to join. Before
    /// joining, every host must resolve the domain (point its DNS at a domain controller) and keep its clock
    /// close to the DC's (Kerberos). Current Windows DCs want LDAPS (ldaps="true"), which also needs the pool
    /// to trust the DC's CA certificate (Pool.install_trusted_certificate with purpose "ldaps"). new_user is
    /// the account to grant a role to; its subject identity is looked up against the directory, so it has to
    /// be a real account there too. A pool already joined to this domain is used as it is - and left joined.
    /// The defaults are placeholders: pass your own domain, administrator account and user.
    /// </remarks>
    public static void ManageAdUsers(string url, string user, string password, string domain = "",
        string adminUser = "alice", string adminPassword = "Password1", string newUser = "alice",
        string ldaps = "false")
    {
        var session = Connect(url, user, password);
        var pool = Pool.get_all(session)[0].opaque_ref;
        var coordinator = Pool.get_master(session, pool).opaque_ref;
        var alreadyJoined = !string.IsNullOrEmpty(domain)
            && Host.get_external_auth_type(session, coordinator) == "AD"
            && string.Equals(Host.get_external_auth_service_name(session, coordinator), domain,
                StringComparison.OrdinalIgnoreCase);
        if (alreadyJoined)
        {
            Console.WriteLine($"Already joined to domain: {domain}");
        }
        else
        {
            Pool.enable_external_auth(session, pool,
                new Dictionary<string, string> { ["user"] = adminUser, ["pass"] = adminPassword, ["ldaps"] = ldaps },
                domain, "AD");
            Console.WriteLine($"Joined domain: {(string.IsNullOrEmpty(domain) ? "(none given)" : domain)}");
        }

        var subjectName = string.IsNullOrEmpty(domain) ? newUser : $"{newUser}@{domain}";
        var sid = Auth.get_subject_identifier(session, subjectName);
        var info = Auth.get_subject_information_from_identifier(session, sid);
        // other_config/roles are accepted here but discarded by real xapi (it re-derives other_config
        // from AD itself, and roles isn't a settable constructor field) - subject.add_to_roles below is
        // the call that actually matters.
        var subject = Subject.create(session, new Subject
        {
            subject_identifier = sid,
            other_config = new Dictionary<string, string>(),
            roles = new List<XenRef<Role>>(),
        }).opaque_ref;
        var adminRole = Role.get_by_name_label(session, "pool-admin")[0];
        Subject.add_to_roles(session, subject, adminRole);
        Console.WriteLine($"Added subject {info["subject-displayname"]} ({info["subject-name"]}) as " +
            string.Join(", ", Subject.get_roles(session, subject).Select(r => Role.get_name_label(session, r.opaque_ref))));

        // Revoking access does not end sessions the user already has: logging the subject out is a
        // separate act, and the one that actually gets them off the pool now rather than at next login.
        Console.WriteLine($"Logged-in subjects: {Session.get_all_subject_identifiers(session).Length}");
        Session.logout_subject_identifier(session, sid);
        Console.WriteLine($"  logged out {info["subject-name"]}");

        Subject.remove_from_roles(session, subject, adminRole);
        Subject.destroy(session, subject);
        if (!alreadyJoined)
        {
            // Leave the way it was found. Passing the admin credentials also removes the pool's
            // computer accounts from the directory; with {} they stay behind in AD.
            Pool.disable_external_auth(session, pool,
                new Dictionary<string, string> { ["user"] = adminUser, ["pass"] = adminPassword });
        }
        Console.WriteLine("OK: manage-ad-users");
        session.logout();
    }
}
