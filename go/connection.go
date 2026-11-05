// Connecting to a pool: log in (the Go binding skips certificate validation for https URLs, which
// suits a host's self-signed certificate) and follow HOST_IS_SLAVE to the coordinator when given a
// pool member.

package main

import (
	"regexp"
	"strings"

	"go/xenapi"
)

// --- connect ---
func connect(url, user, password string) *xenapi.Session {
	session, err := login(url, user, password)
	if err == nil {
		return session
	}
	// A pool member names the coordinator's address; reconnect there (assuming the coordinator is up).
	coordinator := coordinatorFromSlaveError(err)
	if coordinator == "" {
		panic(err)
	}
	session, err = login("https://"+coordinator, user, password)
	if err != nil {
		panic(err)
	}
	return session
}

func login(url, user, password string) (*xenapi.Session, error) {
	session := xenapi.NewSession(&xenapi.ClientOpts{URL: url})
	_, err := session.LoginWithPassword(user, password, "1.0", "sdk-examples")
	return session, err
}

// coordinatorFromSlaveError returns the coordinator address carried by a HOST_IS_SLAVE error, or "".
// The Go binding surfaces API errors as a formatted string, rendering the error's data slice (the full
// XenAPI description, [code, ...params]) as "data [HOST_IS_SLAVE <addr>]" - so we recognise the code and
// take the address, which is the last element of that slice.
func coordinatorFromSlaveError(err error) string {
	msg := err.Error()
	if !strings.Contains(msg, xenapi.ErrorHostIsSlave) {
		return ""
	}
	if m := regexp.MustCompile(`data \[(.+)\]`).FindStringSubmatch(msg); m != nil {
		if fields := strings.Fields(m[1]); len(fields) > 0 {
			return fields[len(fields)-1]
		}
	}
	return ""
}
