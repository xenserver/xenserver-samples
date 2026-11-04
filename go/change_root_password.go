package main

import (
	"fmt"

	"go/xenapi"
)

// changeRootPassword - Change the root password.
//
// Change the local superuser password, handle the wrong-old-password failure, and change it back.
func changeRootPassword(url, user, password string) {
	session := connect(url, user, password)
	const temporary = "sdk-example-temp-password"

	// ChangePassword takes the OLD password as well as the new one, even though you are already
	// authenticated.
	check(session.ChangePassword(password, temporary))
	fmt.Println("Password changed.")
	// Whatever happens next, put the password back: a failure part-way would otherwise leave root on
	// the temporary one.
	restored := false
	defer func() {
		if !restored {
			session.ChangePassword(temporary, password)
		}
	}()

	// The existing session stays valid afterwards - only NEW connections need the new password.
	pools, err := xenapi.Pool.GetAll(session)
	check(err)
	fmt.Printf("Session still usable: %t\n", len(pools) == 1)

	// session.change_password on a ROOT session ignores old_pwd entirely (CA-13567, confirmed in
	// xapi_session.ml) - any string would also be accepted, so there is no "wrong old password is
	// rejected" failure to demonstrate here. The real gate is upstream of that: only a session
	// authenticated as the local superuser may call this at all. The Go binding keeps its session
	// id private, so check that the same way the RRD/export examples obtain one of their own - with
	// the NEW password, which is the one any new connection needs now.
	sid := rawLogin(url, user, temporary)
	isSuperuser := rawRPC(url, "session.get_is_local_superuser", sid, sid)
	fmt.Printf("Allowed because session.is_local_superuser = %s\n", isSuperuser)
	rawRPC(url, "session.logout", sid)

	check(session.ChangePassword(temporary, password))
	restored = true
	fmt.Println("Password restored.")
	fmt.Println("OK: change-root-password")
	session.Logout()
}
