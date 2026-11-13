package main

import (
	"crypto/rand"
	"fmt"

	"go/xenapi"
)

// traceAPICalls sends a W3C trace context (a traceparent header) with every call, so the work the pool
// does for them is recorded as part of your application's distributed trace. ClientOpts.Headers are
// sent with every request a session makes. In an application instrumented with OpenTelemetry you would
// take the traceparent from the current span (otel.GetTextMapPropagator().Inject) rather than make one
// up as this does.
//
// Run it:
//
//	traceAPICalls("https://xenserver", "root", password)
func traceAPICalls(url, user, password string) {
	// version 00, a 16-byte trace id, the 8-byte id of the calling span, and flags 01 (sampled)
	traceID, spanID := make([]byte, 16), make([]byte, 8)
	_, err := rand.Read(traceID)
	check(err)
	_, err = rand.Read(spanID)
	check(err)
	traceparent := fmt.Sprintf("00-%x-%x-01", traceID, spanID)

	login := func(url string) (*xenapi.Session, error) {
		session := xenapi.NewSession(&xenapi.ClientOpts{URL: url, Headers: map[string]string{"traceparent": traceparent}})
		_, err := session.LoginWithPassword(user, password, "1.0", "sdk-examples")
		return session, err
	}
	session, err := login(url)
	if err != nil {
		if coordinator := coordinatorFromSlaveError(err); coordinator != "" {
			session, err = login("https://" + coordinator) // the coordinator, as connect does
		}
	}
	check(err)
	fmt.Printf("Trace %x: each call sends traceparent: %s\n", traceID, traceparent)

	hosts, err := xenapi.Host.GetAll(session)
	check(err)
	fmt.Printf("The pool has %d hosts\n", len(hosts))
	fmt.Println("OK: trace-api-calls")
	session.Logout()
}
