package main

import (
	"fmt"
	"os"
	"regexp"
	"sort"
	"strings"
	"time"

	"go/xenapi"
)

// wlbRecommendations needs a real, reachable WLB appliance: pool.InitializeWlb makes a synchronous
// HTTP call to it and raises WLB_CONNECTION_REFUSED/WLB_CONNECTION_RESET if it can't connect -
// there is no way to fake this with a placeholder. wlbHostPort is host:port, with no URL scheme -
// that is the real wire format (xe pool-initialize-wlb wlb_url="10.x.x.x:30601" ...), not a URL.
//
// The pool checks the appliance's TLS certificate (pool.wlb_verify_cert), and only against the
// certificates installed with Pool.CertificateInstall - not install_trusted_certificate's. A fresh
// appliance has a self-signed one, so pass it as wlbCertificate (a PEM file): without it
// InitializeWlb fails with INTERNAL_ERROR "Connection failed: configuration failed." and no hint
// that the certificate is the reason.
func wlbRecommendations(url, user, password, vmName, wlbHostPort, wlbUsername, wlbPassword, wlbCertificate string) {
	session := connect(url, user, password)
	// Deferred first, so it runs LAST: after the deferred WLB tidy-up below, which needs the session.
	defer session.Logout()

	certName := ""
	if wlbCertificate != "" {
		certName = "sdk-example-wlb.pem"
		cert, err := os.ReadFile(wlbCertificate)
		check(err)
		check(xenapi.Pool.CertificateInstall(session, certName, string(cert))) // pool-wide: no pool argument
	}
	check(xenapi.Pool.InitializeWlb(session, wlbHostPort, wlbUsername, wlbPassword, user, password))
	defer func() {
		// Disconnect from the appliance however the above went, or the pool stays attached to it.
		check(xenapi.Pool.DeconfigureWlb(session))
		if certName != "" {
			check(xenapi.Pool.CertificateUninstall(session, certName))
		}
	}()

	// Initializing connects the pool to the appliance but leaves balancing off: every WLB call after
	// this would fail WLB_DISABLED until it's switched on.
	pools, err := xenapi.Pool.GetAll(session)
	check(err)
	check(xenapi.Pool.SetWlbEnabled(session, pools[0], true))
	wlbURL, _ := xenapi.Pool.GetWlbURL(session, pools[0])
	fmt.Printf("WLB: %s\n", wlbURL)

	// Read BY POSITION, and the two calls do not share a shape. The pool's are keyed by VM and say
	// where to move it: [0] "wlb", [1] the destination host's UUID (a uuid, not a ref), [2] and [3]
	// ids, [4] the reason.
	poolRecs, err := xenapi.Pool.RetrieveWlbRecommendations(session)
	check(err)
	for vmRef, fields := range poolRecs {
		name, _ := xenapi.VM.GetNameLabel(session, vmRef)
		fmt.Printf("  move %s -> host %s (%s)\n", name, fields[1], fields[4])
	}

	// A VM's own are keyed by host and star-rate each destination: [0] "wlb", [1] the rating - higher
	// is better (a real appliance rated hosts 6.1 here, so not capped at XenCenter's five stars).
	// Right after connecting, the appliance is still discovering the pool and answers
	// WLB_INTERNAL_ERROR 4024 ("Pool discovery has not been started"), 4025 ("... has not been
	// completed"), then 4016 ("WLB does not have current metrics") - keep asking for a while.
	vms, err := xenapi.VM.GetByNameLabel(session, vmName)
	check(err)
	deadline := time.Now().Add(10 * time.Minute)
	var vmRecs map[xenapi.HostRef][]string
	for {
		vmRecs, err = xenapi.VM.RetrieveWlbRecommendations(session, vms[0])
		if err == nil || !isWlbStillDiscovering(err) || time.Now().After(deadline) {
			check(err)
			break
		}
		time.Sleep(15 * time.Second)
	}
	for hostRef, fields := range vmRecs {
		name, _ := xenapi.Host.GetNameLabel(session, hostRef)
		fmt.Printf("  %s rated %s\n", name, fields[1])
	}

	// The appliance's own settings are read and written as one flat map of strings. Send a nightly
	// reporting schedule, then read the configuration back to confirm it took.
	check(xenapi.Pool.SendWlbConfiguration(session, map[string]string{"ReportingCronString": "0 3 * * *"}))
	config, err := xenapi.Pool.RetrieveWlbConfiguration(session)
	check(err)
	keys := make([]string, 0, len(config))
	for k := range config {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	pairs := make([]string, 0, len(keys))
	for _, k := range keys {
		pairs = append(pairs, fmt.Sprintf("%s=%s", k, config[k]))
	}
	fmt.Printf("  appliance configuration: %s\n", strings.Join(pairs, ", "))

	fmt.Println("OK: wlb-recommendations")
}

// isWlbStillDiscovering reports whether err is a WLB_INTERNAL_ERROR whose WLB code is 4024, 4025 or
// 4016 - the appliance is still discovering the pool, or has no metrics for it yet. See
// coordinatorFromSlaveError for why the data slice has to be parsed out of the formatted error string.
func isWlbStillDiscovering(err error) bool {
	msg := err.Error()
	if !strings.Contains(msg, xenapi.ErrorWlbInternalError) {
		return false
	}
	m := regexp.MustCompile(`data \[(.+)\]`).FindStringSubmatch(msg)
	if m == nil {
		return false
	}
	fields := strings.Fields(m[1])
	// The binding prints the code in the message and only its parameters in data: [4024 Pool ...].
	return len(fields) > 0 && (fields[0] == "4024" || fields[0] == "4025" || fields[0] == "4016")
}
