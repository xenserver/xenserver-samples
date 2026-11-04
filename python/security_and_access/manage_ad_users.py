"""Manage Active Directory users.

Join the pool to an Active Directory domain, grant an AD user access with an RBAC role, read it
back, then tidy up.
"""

from connection import connect


def manage_ad_users(url, username, password, domain="", admin_user="alice",
                     admin_password="Password1", new_user="alice", ldaps="false"):
    """Join AD, add a user as a subject with an RBAC role, read it back, then tidy up.

    Needs a real, reachable AD domain controller - enable_external_auth fails at the very first
    call (DNS/LDAP/Kerberos) without one, so domain/admin_user/admin_password have to identify a
    real domain to join. Before joining, every host must resolve the domain (point its DNS at a
    domain controller) and keep its clock close to the DC's (Kerberos). Current Windows DCs want
    LDAPS (ldaps="true"), which also needs the pool to trust the DC's CA certificate
    (pool.install_trusted_certificate with purpose "ldaps"). new_user is the account to grant a
    role to; its subject identity is looked up against the directory, so it has to be a real
    account there too. A pool already joined to this domain is used as it is - and left joined.
    The defaults are placeholders: pass your own domain, administrator account and user."""
    session = connect(url, username, password)
    pool = session.xenapi.pool.get_all()[0]
    coordinator = session.xenapi.pool.get_master(pool)
    already_joined = (domain and session.xenapi.host.get_external_auth_type(coordinator) == "AD"
                      and session.xenapi.host.get_external_auth_service_name(coordinator).lower()
                      == domain.lower())
    if already_joined:
        print("Already joined to domain: %s" % domain)
    else:
        session.xenapi.pool.enable_external_auth(
            pool, {"user": admin_user, "pass": admin_password, "ldaps": ldaps}, domain, "AD")
        print("Joined domain: %s" % (domain or "(none given)"))

    subject_name = "%s@%s" % (new_user, domain) if domain else new_user
    sid = session.xenapi.auth.get_subject_identifier(subject_name)
    info = session.xenapi.auth.get_subject_information_from_identifier(sid)
    # other_config/roles are accepted here but discarded by real xapi (it re-derives other_config
    # from AD itself, and roles isn't a settable constructor field) - subject.add_to_roles below is
    # the call that actually matters.
    subject = session.xenapi.subject.create({"subject_identifier": sid, "other_config": {}, "roles": []})
    admin_role = session.xenapi.role.get_by_name_label("pool-admin")[0]
    session.xenapi.subject.add_to_roles(subject, admin_role)
    roles = [session.xenapi.role.get_name_label(r) for r in session.xenapi.subject.get_roles(subject)]
    print("Added subject %s (%s) as %s"
          % (info["subject-displayname"], info["subject-name"], ", ".join(roles)))

    # Revoking access does not end sessions the user already has: logging the subject out is a
    # separate act, and the one that actually gets them off the pool now rather than at next login.
    print("Logged-in subjects: %d" % len(session.xenapi.session.get_all_subject_identifiers()))
    session.xenapi.session.logout_subject_identifier(sid)
    print("  logged out %s" % info["subject-name"])

    session.xenapi.subject.remove_from_roles(subject, admin_role)
    session.xenapi.subject.destroy(subject)
    if not already_joined:
        # Leave the way it was found. Passing the admin credentials also removes the pool's computer
        # accounts from the directory; with {} they stay behind in AD.
        session.xenapi.pool.disable_external_auth(pool, {"user": admin_user, "pass": admin_password})
    print("OK: manage-ad-users")
    session.logout()
