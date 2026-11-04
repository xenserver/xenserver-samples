# Manage Active Directory users.
#
# Join the pool to an Active Directory domain, grant an AD user access with an RBAC role, read it back, then
# tidy up.
#
# Run it:
#   ./workflows.sh manage-ad-users https://xenserver root "$password"
#
# Optional key=value arguments (default):
#   domain ("")
#   admin_user (alice)
#   admin_password (Password1)
#   new_user (alice)
#   ldaps (false)

# Needs a real, reachable AD domain controller - pool-enable-external-auth fails at the very first call
# (DNS/LDAP/Kerberos) without one, so domain/admin_user/admin_password have to identify a real domain to
# join. Before joining, every host must resolve the domain (point its DNS at a domain controller) and
# keep its clock close to the DC's (Kerberos). Current Windows DCs want LDAPS (ldaps=true), which also
# needs the pool to trust the DC's CA certificate (pool-certificate-install ... purpose=ldaps, i.e.
# install_trusted_certificate). new_user is the account to grant a role to; its subject identity is
# looked up against the directory, so it has to be a real account there too. A pool already joined to
# this domain is used as it is - and left joined. The defaults are placeholders: pass your own domain,
# administrator account and user.
manage_ad_users() {
    local domain admin_user admin_password new_user ldaps subject_name master auth_type auth_service already_joined=false
    domain=$(param domain "")
    admin_user=$(param admin_user "alice")
    admin_password=$(param admin_password "Password1")
    new_user=$(param new_user "alice")
    ldaps=$(param ldaps "false")
    subject_name=$new_user; [ -n "$domain" ] && subject_name="$new_user@$domain"

    pool=$(xe pool-list --minimal)
    master=$(xe pool-param-get uuid=$pool param-name=master)
    auth_type=$(xe host-param-get uuid=$master param-name=external-auth-type)
    auth_service=$(xe host-param-get uuid=$master param-name=external-auth-service-name)
    if [ -n "$domain" ] && [ "$auth_type" = "AD" ] \
        && [ "${auth_service,,}" = "${domain,,}" ]; then
        already_joined=true
        echo "Already joined to domain: $domain"
    else
        xe pool-enable-external-auth uuid=$pool auth-type=AD service-name="$domain" \
            config:user="$admin_user" config:pass="$admin_password" config:ldaps=$ldaps
        echo "Joined domain: ${domain:-(none given)}"
    fi
    subj=$(xe subject-add subject-name="$subject_name")
    xe subject-role-add uuid=$subj role-name=pool-admin
    name=$(xe subject-param-get uuid=$subj param-name=other-config param-key=subject-displayname)
    echo "Added subject $name with role pool-admin"

    # Revoking access does not end sessions the user already has: logging the subject out is a
    # separate act, and the one that actually gets them off the pool now rather than at next login.
    sid=$(xe subject-param-get uuid=$subj param-name=subject-identifier)
    xe session-subject-identifier-logout subject-identifier=$sid
    echo "  logged out $name"

    xe subject-remove subject-uuid=$subj
    if [ "$already_joined" = false ]; then
        # Leave the way it was found. Passing the admin credentials also removes the pool's computer
        # accounts from the directory; without them they stay behind in AD.
        xe pool-disable-external-auth uuid=$pool config:user="$admin_user" config:pass="$admin_password"
    fi
    echo "OK: manage-ad-users"
}
