// Small helpers several workflows share: error checking, finding objects by name, waiting for the
// guest agent, tidying up what an example created.

package main

import (
	"bytes"
	"crypto/tls"
	"encoding/json"
	"encoding/xml"
	"fmt"
	"net/http"
	"regexp"
	"strings"
	"time"

	"go/xenapi"
)

func check(err error) {
	if err != nil {
		panic(err)
	}
}

// templateByName finds a template VM by its exact name (rather than picking an arbitrary one).
func templateByName(session *xenapi.Session, name string) xenapi.VMRef {
	vms, err := xenapi.VM.GetAllRecords(session)
	check(err)
	for ref, vm := range vms {
		if vm.IsATemplate && vm.NameLabel == name {
			return ref
		}
	}
	panic(fmt.Sprintf("no template named %q was found", name))
}

// vmByName finds a guest VM (not a template, control domain or snapshot) by its exact name.
func vmByName(session *xenapi.Session, name string) xenapi.VMRef {
	vms, err := xenapi.VM.GetAllRecords(session)
	check(err)
	for ref, vm := range vms {
		if !vm.IsATemplate && !vm.IsControlDomain && !vm.IsASnapshot && vm.NameLabel == name {
			return ref
		}
	}
	panic(fmt.Sprintf("no VM named %q was found", name))
}

// srByName finds an SR by its exact name (optionally requiring it to be shared).
func srByName(session *xenapi.Session, name string, shared bool) xenapi.SRRef {
	srs, err := xenapi.SR.GetAllRecords(session)
	check(err)
	for ref, sr := range srs {
		if sr.NameLabel == name && (!shared || sr.Shared) {
			return ref
		}
	}
	panic(fmt.Sprintf("no SR named %q was found", name))
}

// detachAndForgetSR detaches an SR from every host, then forgets it: XenCenter's Detach followed by
// Forget. SR.Forget refuses an SR that is still attached (SR_HAS_PBD), so unplug its PBDs first.
// Forgetting drops the pool's record of the SR but leaves the data on the storage itself.
func detachAndForgetSR(session *xenapi.Session, sr xenapi.SRRef) {
	pbds, err := xenapi.SR.GetPBDs(session, sr)
	check(err)
	for _, pbd := range pbds {
		attached, err := xenapi.PBD.GetCurrentlyAttached(session, pbd)
		check(err)
		if attached {
			check(xenapi.PBD.Unplug(session, pbd))
		}
	}
	check(xenapi.SR.Forget(session, sr))
}

// provision is VM.Provision, after filling in the SR for every disk the template describes. A template's
// other_config["disks"] names each disk's SR as sr="" (empty); a real host takes that literally and
// VM.Provision fails with UUID_INVALID, so point the disks at the pool's default SR first - exactly what
// `xe vm-install` does before calling VM.provision itself.
func provision(session *xenapi.Session, vm xenapi.VMRef) {
	otherConfig, err := xenapi.VM.GetOtherConfig(session, vm)
	check(err)
	if disks, ok := otherConfig["disks"]; ok && strings.Contains(disks, `sr=""`) {
		pools, err := xenapi.Pool.GetAll(session)
		check(err)
		defaultSR, err := xenapi.Pool.GetDefaultSR(session, pools[0])
		check(err)
		srUUID, err := xenapi.SR.GetUUID(session, defaultSR)
		check(err)
		check(xenapi.VM.RemoveFromOtherConfig(session, vm, "disks"))
		check(xenapi.VM.AddToOtherConfig(session, vm, "disks", strings.ReplaceAll(disks, `sr=""`, `sr="`+srUUID+`"`)))
	}
	check(xenapi.VM.Provision(session, vm))
}

// copyOfGuest makes a throwaway VM with a working guest OS: a copy of an existing VM that has one.
//
// Suspend, checkpoint, live migration and clean shutdown all need the guest's cooperation: on a
// running VM with no PV drivers xapi refuses them up front with VM_LACKS_FEATURE (a VM freshly
// cloned from a template has no OS at all). So copy a VM that does have an OS and PV drivers,
// without disturbing it: snapshot it (fine while it runs), clone the snapshot - a clone of a
// snapshot is a template - and provision that into an ordinary VM. The snapshot is only needed for
// the clone, so it goes again straight away.
func copyOfGuest(session *xenapi.Session, sourceVMName, newVMName string) xenapi.VMRef {
	source := vmByName(session, sourceVMName)
	snapshot, err := xenapi.VM.Snapshot(session, source, newVMName+"-source", nil)
	check(err)
	vm, err := xenapi.VM.Clone(session, snapshot, newVMName)
	check(err)
	provision(session, vm)
	destroyVMAndDisks(session, snapshot)
	return vm
}

// waitForGuestAgent waits, after VM.Start, until the guest's PV drivers have reported in.
//
// xapi only offers the guest-dependent operations once the guest says it can do them, and
// allowed_operations is where it says so: wait for clean_shutdown to appear there (the same check
// that refuses it with VM_LACKS_FEATURE beforehand). A booting OS takes a while.
// guestAgentReady: clean_shutdown in allowed_operations says the guest can shut down; a Linux kernel offers
// that early in boot, before the agent runs (hot-plug needs the agent, and suspend needs its emulated disk
// unplugged), so the guest metrics must report the PV drivers too.
func guestAgentReady(session *xenapi.Session, vm xenapi.VMRef) bool {
	ops, err := xenapi.VM.GetAllowedOperations(session, vm)
	check(err)
	canShutDown := false
	for _, op := range ops {
		canShutDown = canShutDown || op == xenapi.VMOperationsCleanShutdown
	}
	if !canShutDown {
		return false
	}
	metrics, err := xenapi.VM.GetGuestMetrics(session, vm)
	check(err)
	if metrics == xenapi.VMGuestMetricsRef("OpaqueRef:NULL") {
		return false
	}
	detected, err := xenapi.VMGuestMetrics.GetPVDriversDetected(session, metrics)
	check(err)
	return detected
}

func waitForGuestAgent(session *xenapi.Session, vm xenapi.VMRef) {
	const timeout = 300 * time.Second
	const interval = 2 * time.Second
	deadline := time.Now().Add(timeout)
	for {
		if guestAgentReady(session, vm) {
			return
		}
		if time.Now().After(deadline) {
			panic(fmt.Sprintf("the guest's PV drivers did not report in within %s; does the source "+
				"VM have a guest OS with PV drivers (XenServer VM Tools)?", timeout))
		}
		time.Sleep(interval)
	}
}

// probeForFailure runs SR.probe's deliberately-incomplete discovery call and returns the XML
// fragment its failure carries describing what it found. The New SR wizard discovers iSCSI/HBA
// LUNs by asking with an incomplete device-config on purpose: the backend can't create anything
// from it yet, so it fails with an error whose params carry an XML fragment describing what it
// found. A probe that unexpectedly succeeds means the device-config was already complete - not the
// discovery prompt this helper is looking for. Never fall back to SR.create instead: on real
// storage a create that unexpectedly succeeds formats the LUN.
func probeForFailure(session *xenapi.Session, host xenapi.HostRef, deviceConfig map[string]string, smType string) string {
	_, err := xenapi.SR.Probe(session, host, deviceConfig, smType, map[string]string{})
	if err == nil {
		panic(fmt.Sprintf("SR.probe for %s succeeded without asking for more information; "+
			"check the target address", smType))
	}
	if xml := xmlFromFailure(err); xml != "" {
		return xml
	}
	panic(err)
}

// xmlFromFailure pulls the XML fragment out of a XenAPI failure's text. The Go binding renders an
// API error as a formatted string ending "... data [<code> <param> <param> ...]" (see
// coordinatorFromSlaveError) rather than keeping the params as separate values, so splitting on
// whitespace would break up the XML itself wherever it contains one. The XML fragment is always
// the last parameter in these errors, so take everything from the first "<" onward instead.
func xmlFromFailure(err error) string {
	msg := err.Error()
	i := strings.Index(msg, "data [")
	if i < 0 {
		return ""
	}
	inner := strings.TrimSuffix(msg[i+len("data ["):], "]")
	if j := strings.Index(inner, "<"); j >= 0 {
		return inner[j:]
	}
	return ""
}

// enableWhenBooted re-enables a host that has just come back. It reports itself live before xapi
// on it has finished starting, and until then Host.Enable fails HOST_STILL_BOOTING - so retry that.
func enableWhenBooted(session *xenapi.Session, host xenapi.HostRef) {
	deadline := time.Now().Add(600 * time.Second)
	for {
		err := xenapi.Host.Enable(session, host)
		if err == nil {
			return
		}
		if failureCode(err) != xenapi.ErrorHostStillBooting || time.Now().After(deadline) {
			panic(err)
		}
		time.Sleep(10 * time.Second)
	}
}

// waitForRestart waits for a host to come back from a reboot (key "boot_time") or toolstack
// restart ("agent_start_time"): until that other_config entry differs from before and the host is
// live. It reconnects every time round, because the host restarting may be the coordinator this
// session talks to; returns the new session.
func waitForRestart(url, user, password, hostUUID, key, before string) (session *xenapi.Session) {
	deadline := time.Now().Add(1800 * time.Second)
	for {
		ready := func() (ok bool) {
			defer func() {
				if recover() != nil { // down, or xapi still starting
					ok = false
				}
			}()
			session = connect(url, user, password)
			host, err := xenapi.Host.GetByUUID(session, hostUUID)
			check(err)
			otherConfig, err := xenapi.Host.GetOtherConfig(session, host)
			check(err)
			return otherConfig[key] != before && hostLive(session, host)
		}()
		if ready {
			return session
		}
		if session != nil {
			session.Logout()
		}
		if time.Now().After(deadline) {
			panic(fmt.Sprintf("host %s did not come back in time", hostUUID))
		}
		time.Sleep(10 * time.Second)
	}
}

// moveDisksToSR relocates every one of a (not-yet-started) VM's disks onto the given SR, the same
// VDI.PoolMigrate call storage-migrate already demonstrates.
func moveDisksToSR(session *xenapi.Session, vm xenapi.VMRef, sr xenapi.SRRef) {
	for _, vdi := range diskVdis(session, vm) {
		current, err := xenapi.VDI.GetSR(session, vdi)
		check(err)
		if current != sr {
			_, err := xenapi.VDI.PoolMigrate(session, vdi, sr, map[string]string{})
			check(err)
		}
	}
}

// introduceUpdateRepositories introduces the pool's update repositories the way XenCenter does: the
// release's base packages (update=false) and its update stream (update=true, which
// Pool.SyncUpdates needs - otherwise NO_REPOSITORY_ENABLED). A real host checks the URLs
// (INVALID_BASE_URL for an unknown domain), so these are the XenServer CDN's, e.g.
// https://repo.ops.xenserver.com/xs9/{base,normal}.
func introduceUpdateRepositories(session *xenapi.Session, repoURL, sourceURL string) []xenapi.RepositoryRef {
	var repos []xenapi.RepositoryRef
	for _, stage := range []string{"base", "normal"} {
		repo, err := xenapi.Repository.Introduce(session, "sdk-example-"+stage,
			"SDK example "+stage+" repository",
			repoURL+"/"+stage, sourceURL+"/"+stage, stage != "base", "")
		check(err)
		repos = append(repos, repo)
	}
	return repos
}

// diskVdis returns the VDIs backing a VM's disk VBDs (used to clean up a VM's owned disks).
func diskVdis(session *xenapi.Session, vmRef xenapi.VMRef) []xenapi.VDIRef {
	var vdis []xenapi.VDIRef
	vbds, err := xenapi.VM.GetVBDs(session, vmRef)
	check(err)
	for _, vbd := range vbds {
		t, err := xenapi.VBD.GetType(session, vbd)
		check(err)
		if t != xenapi.VbdTypeDisk {
			continue
		}
		vdi, err := xenapi.VBD.GetVDI(session, vbd)
		check(err)
		if vdi != xenapi.VDIRef("OpaqueRef:NULL") {
			vdis = append(vdis, vdi)
		}
	}
	return vdis
}

// destroyVMAndDisks destroys a VM (or snapshot, or template) an example made, and the disks it owns.
// VM.Destroy removes only the VM record and leaves its disks behind, so collect them first and destroy
// them afterwards - exactly what deleteVM does by hand.
func destroyVMAndDisks(session *xenapi.Session, vm xenapi.VMRef) {
	vdis := diskVdis(session, vm)
	// A checkpoint (or a suspended VM) also owns a suspend image holding its memory, which no VBD
	// points at: destroy that as well.
	suspendVDI, err := xenapi.VM.GetSuspendVDI(session, vm)
	check(err)
	if suspendVDI != "OpaqueRef:NULL" {
		vdis = append(vdis, suspendVDI)
	}
	check(xenapi.VM.Destroy(session, vm))
	for _, vdi := range vdis {
		check(xenapi.VDI.Destroy(session, vdi))
	}
}

// containsGuidance reports whether a host's pending_guidances includes the named one.
func containsGuidance(guidance []xenapi.UpdateGuidances, want xenapi.UpdateGuidances) bool {
	for _, g := range guidance {
		if g == want {
			return true
		}
	}
	return false
}

// findXMLElement is firstXMLElement for the first <tag> whose child <key> has the given text (any
// <tag>, when value is "").
func findXMLElement(xmlText, tag, key, value string) map[string]string {
	decoder := xml.NewDecoder(strings.NewReader(xmlText))
	for {
		tok, err := decoder.Token()
		if err != nil {
			panic(fmt.Sprintf("no <%s> element found in: %s", tag, xmlText))
		}
		start, ok := tok.(xml.StartElement)
		if !ok || start.Name.Local != tag {
			continue
		}
		var raw struct {
			Fields []struct {
				XMLName xml.Name
				Value   string `xml:",chardata"`
			} `xml:",any"`
		}
		check(decoder.DecodeElement(&raw, &start))
		fields := map[string]string{}
		for _, f := range raw.Fields {
			fields[f.XMLName.Local] = f.Value
		}
		if value == "" || fields[key] == value {
			return fields
		}
	}
}

// failureCode picks the XenAPI error code out of the binding's error text. A failure arrives as a plain
// error whose message is the code followed by its arguments, so the code is the leading run of capitals.
var errorCodePattern = regexp.MustCompile(`[A-Z][A-Z0-9_]{3,}`)

func failureCode(err error) string {
	if code := errorCodePattern.FindString(err.Error()); code != "" {
		return code
	}
	return err.Error()
}

// srLabel is an SR's name, tolerating the null reference an unset pool field holds.
func srLabel(session *xenapi.Session, sr xenapi.SRRef) string {
	if sr == "" || sr == "OpaqueRef:NULL" {
		return "(none)"
	}
	name, err := xenapi.SR.GetNameLabel(session, sr)
	check(err)
	return name
}

// rawRPC makes a JSON-RPC call with an explicit session id — for the one thing the Go binding cannot
// express, a session it did not create itself.
func rawRPC(url, method string, params ...any) json.RawMessage {
	result, failure := rawRPCCall(url, method, params...)
	if failure != nil {
		panic(fmt.Sprintf("%s failed: %s", method, failure))
	}
	return result
}

// rawRPCCall is rawRPC that returns a XenAPI failure (the JSON-RPC error) instead of panicking on it.
func rawRPCCall(url, method string, params ...any) (json.RawMessage, json.RawMessage) {
	body, err := json.Marshal(map[string]any{
		"jsonrpc": "2.0", "id": 1, "method": method, "params": params,
	})
	check(err)
	resp, err := insecureClient().Post(url+"/jsonrpc", "application/json", bytes.NewReader(body))
	check(err)
	defer resp.Body.Close()
	var r struct {
		Result json.RawMessage `json:"result"`
		Error  json.RawMessage `json:"error"`
	}
	check(json.NewDecoder(resp.Body).Decode(&r))
	if len(r.Error) > 0 && string(r.Error) != "null" {
		return nil, r.Error
	}
	return r.Result, nil
}

func hostLive(session *xenapi.Session, host xenapi.HostRef) bool {
	metrics, err := xenapi.Host.GetMetrics(session, host)
	check(err)
	live, err := xenapi.HostMetrics.GetLive(session, metrics)
	check(err)
	return live
}

func insecureClient() *http.Client {
	return &http.Client{Transport: &http.Transport{TLSClientConfig: &tls.Config{InsecureSkipVerify: true}}}
}

// rawLogin obtains a session id via a plain JSON-RPC call (for the HTTP-only rrd_updates endpoint).
func rawLogin(url, user, password string) string {
	body := fmt.Sprintf(`{"jsonrpc":"2.0","id":1,"method":"session.login_with_password","params":[%q,%q,"1.0","rrd"]}`, user, password)
	resp, err := insecureClient().Post(url+"/jsonrpc", "application/json", strings.NewReader(body))
	check(err)
	defer resp.Body.Close()
	var r struct {
		Result string `json:"result"`
		Error  *struct {
			Message string   `json:"message"`
			Data    []string `json:"data"`
		} `json:"error"`
	}
	check(json.NewDecoder(resp.Body).Decode(&r))
	if r.Error != nil {
		// A pool member names the coordinator's address; log in there instead, as connect does.
		if r.Error.Message == xenapi.ErrorHostIsSlave && len(r.Error.Data) > 0 {
			return rawLogin("https://"+r.Error.Data[0], user, password)
		}
		panic(fmt.Sprintf("login failed: %s %v", r.Error.Message, r.Error.Data))
	}
	return r.Result
}
