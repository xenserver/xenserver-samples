package main

import (
	"fmt"
	"strings"

	"go/xenapi"
)

// manageAdUsers joins AD, adds a user as a subject with an RBAC role, reads it back, then tidies
// up. Needs a real, reachable AD domain controller - EnableExternalAuth fails at the very first
// call (DNS/LDAP/Kerberos) without one, so domain/adminUser/adminPassword have to identify a real
// domain to join. Before joining, every host must resolve the domain (point its DNS at a domain
// controller) and keep its clock close to the DC's (Kerberos). Current Windows DCs want LDAPS
// (ldaps="true"), which also needs the pool to trust the DC's CA certificate
// (xenapi.Pool.InstallTrustedCertificate with purpose "ldaps"). newUser is the account to grant a
// role to; its subject identity is looked up against the directory, so it has to be a real account
// there too. A pool already joined to this domain is used as it is - and left joined. The defaults
// are placeholders: pass your own domain, administrator account and user.
func manageAdUsers(url, user, password, domain, adminUser, adminPassword, newUser, ldaps string) {
	session := connect(url, user, password)

	pools, err := xenapi.Pool.GetAll(session)
	check(err)
	pool := pools[0]
	coordinator, err := xenapi.Pool.GetMaster(session, pool)
	check(err)
	authType, err := xenapi.Host.GetExternalAuthType(session, coordinator)
	check(err)
	authDomain, err := xenapi.Host.GetExternalAuthServiceName(session, coordinator)
	check(err)
	alreadyJoined := domain != "" && authType == "AD" && strings.EqualFold(authDomain, domain)
	if alreadyJoined {
		fmt.Printf("Already joined to domain: %s\n", domain)
	} else {
		check(xenapi.Pool.EnableExternalAuth(session, pool,
			map[string]string{"user": adminUser, "pass": adminPassword, "ldaps": ldaps}, domain, "AD"))
		if domain != "" {
			fmt.Printf("Joined domain: %s\n", domain)
		} else {
			fmt.Println("Joined domain: (none given)")
		}
	}

	subjectName := newUser
	if domain != "" {
		subjectName = newUser + "@" + domain
	}
	sid, err := xenapi.Auth.GetSubjectIdentifier(session, subjectName)
	check(err)
	info, err := xenapi.Auth.GetSubjectInformationFromIdentifier(session, sid)
	check(err)
	subject, err := xenapi.Subject.Create(session, xenapi.SubjectRecord{SubjectIdentifier: sid, OtherConfig: info})
	check(err)

	// role.get_by_name_label is simpler/more idiomatic than filtering get_all_records, and matches
	// what `xe subject-role-add role-name=` does server-side.
	roleRefs, err := xenapi.Role.GetByNameLabel(session, "pool-admin")
	check(err)
	admin := roleRefs[0]
	check(xenapi.Subject.AddToRoles(session, subject, admin))
	assigned, err := xenapi.Subject.GetRoles(session, subject)
	check(err)
	names := ""
	for _, r := range assigned {
		n, _ := xenapi.Role.GetNameLabel(session, r)
		names += n + " "
	}
	fmt.Printf("Added subject %s (%s) as %s\n",
		info["subject-displayname"], info["subject-name"], strings.TrimSpace(names))

	// Revoking access does not end sessions the user already has: logging the subject out is a separate
	// act, and the one that actually gets them off the pool now rather than at next login.
	loggedIn, err := session.GetAllSubjectIdentifiers()
	check(err)
	fmt.Printf("Logged-in subjects: %d\n", len(loggedIn))
	check(session.LogoutSubjectIdentifier(sid))
	fmt.Printf("  logged out %s\n", info["subject-name"])

	check(xenapi.Subject.RemoveFromRoles(session, subject, admin))
	check(xenapi.Subject.Destroy(session, subject))
	if !alreadyJoined {
		// Leave the way it was found. Passing the admin credentials also removes the pool's computer
		// accounts from the directory; with {} they stay behind in AD.
		check(xenapi.Pool.DisableExternalAuth(session, pool,
			map[string]string{"user": adminUser, "pass": adminPassword}))
	}
	fmt.Println("OK: manage-ad-users")
	session.Logout()
}
