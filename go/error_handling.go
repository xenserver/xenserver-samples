package main

import (
	"fmt"

	"go/xenapi"
)

// errorHandling - Handle an API error.
//
// Catch an API failure and inspect its error code and parameters — the shape of every error the API
// returns, and how to react to it robustly.
//
// Run it:
//
//	errorHandling("https://xenserver", "root", password)
func errorHandling(url, user, password string) {
	session := connect(url, user, password)
	// XenAPI errors surface as an error whose text carries the XenAPI error code.
	_, err := xenapi.Host.GetByUUID(session, "this-uuid-does-not-exist")
	if err != nil {
		fmt.Printf("Caught expected failure: %s\n", err)
	} else {
		fmt.Println("unexpected: no error")
	}
	fmt.Println("OK: error-handling")
	session.Logout()
}
