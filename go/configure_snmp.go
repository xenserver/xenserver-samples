package main

import (
	"crypto/rand"
	"encoding/json"
	"fmt"

	"go/xenapi"
)

// configureSnmp - Configure SNMP monitoring.
//
// Configure a host's SNMP agent through the monitoring plugin: read its configuration, enable it
// with a community string, then read the configuration and running status back.
//
// nmss is the list of real trap destinations SNMP notifications go to - an empty list never
// configures where traps actually go, which is the whole point of "configure SNMP monitoring".
// Plugin calls are per-host, so configure every host, and restore each one to disabled again
// afterwards.
func configureSnmp(url, user, password, trapDestination string) {
	session := connect(url, user, password)
	hosts, err := xenapi.Host.GetAll(session)
	check(err)
	config := `{"common":{"enabled":"yes","debug_log":"no"},` +
		`"agent":{"v2c":"yes","v3":"no","community":"sdk-community","user_name":"",` +
		`"authentication_password":"","authentication_protocol":"",` +
		// Each trap destination needs a uuid of its own: the plugin refuses the whole config without one.
		`"privacy_password":"","privacy_protocol":""},"nmss":[{"uuid":"` + newUUID() + `","address":"` + trapDestination + `",` +
		`"port":162,"v2c":"yes","v3":"no","community":"sdk-community","user_name":"",` +
		`"authentication_password":"","authentication_protocol":"",` +
		`"privacy_password":"","privacy_protocol":""}]}`
	for _, host := range hosts {
		snmp := func(fn string, args map[string]string) map[string]interface{} {
			r, e := xenapi.Host.CallPlugin(session, host, "snmp", fn, args)
			check(e)
			var env map[string]interface{}
			check(json.Unmarshal([]byte(r), &env))
			return env
		}
		// The plugin reports a refused config in its answer, not as an API error: check it.
		if answer := snmp("set-config", map[string]string{"config": config}); answer["code"] != float64(0) {
			panic(fmt.Sprintf("set-config refused the configuration: %v", answer["message"]))
		}
		status := snmp("status", map[string]string{})["result"].(map[string]interface{})
		cfg := snmp("get-config", map[string]string{})["result"].(map[string]interface{})
		agent := cfg["agent"].(map[string]interface{})
		nmss, _ := cfg["nmss"].([]interface{})
		label, _ := xenapi.Host.GetNameLabel(session, host)
		fmt.Printf("%s: SNMP enabled: %v / %v\n", label, status["enabled"], status["active"])
		trap := "(none)"
		if len(nmss) > 0 {
			if first, ok := nmss[0].(map[string]interface{}); ok {
				trap = fmt.Sprintf("%v", first["address"])
			}
		}
		fmt.Printf("  community: %v, trap destination: %s\n", agent["community"], trap)
		snmp("set-config", map[string]string{"config": `{"common":{"enabled":"no"}}`}) // restore
	}
	fmt.Println("OK: configure-snmp")
	session.Logout()
}

// newUUID returns a random (version 4) UUID.
func newUUID() string {
	b := make([]byte, 16)
	_, err := rand.Read(b)
	check(err)
	b[6] = b[6]&0x0f | 0x40
	b[8] = b[8]&0x3f | 0x80
	return fmt.Sprintf("%x-%x-%x-%x-%x", b[0:4], b[4:6], b[6:8], b[8:10], b[10:])
}
