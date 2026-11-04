package main

import (
	"encoding/xml"
	"fmt"
	"io"
	"os"
	"strings"

	"go/xenapi"
)

// serverStatusReport - Collect a server status report.
//
// Gather a host's diagnostic bundle: read the catalogue of sections it can report on, download the
// whole bundle, then download a smaller one covering only the sections you pick.
func serverStatusReport(url, user, password string) {
	session := connect(url, user, password)
	defer session.Logout()

	// Report on the coordinator. Each host answers for itself, so which one you ask decides whose logs
	// you get - support normally wants every host, one download each.
	pools, err := xenapi.Pool.GetAll(session)
	check(err)
	host, err := xenapi.Pool.GetMaster(session, pools[0])
	check(err)
	name, err := xenapi.Host.GetNameLabel(session, host)
	check(err)
	fmt.Printf("Status report for %s\n", name)

	// The host publishes a catalogue of the sections it can report on, each with a size estimate and
	// whether it may contain personal data, so a client can offer an informed choice rather than
	// hard-coding the list.
	capabilitiesXML, err := xenapi.Host.GetSystemStatusCapabilities(session, host)
	check(err)
	var catalogue struct {
		Capabilities []struct {
			Key            string `xml:"key,attr"`
			MaxSize        string `xml:"max-size,attr"`
			DefaultChecked string `xml:"default-checked,attr"`
			Pii            string `xml:"pii,attr"`
		} `xml:"capability"`
	}
	check(xml.Unmarshal([]byte(capabilitiesXML), &catalogue))
	var keys, defaults []string
	for _, capability := range catalogue.Capabilities {
		keys = append(keys, capability.Key)
		if capability.DefaultChecked == "yes" {
			defaults = append(defaults, capability.Key)
		}
		fmt.Printf("  %-22s max %9s bytes  default=%-3s pii=%s\n",
			capability.Key, capability.MaxSize, capability.DefaultChecked, capability.Pii)
	}

	// The download is an HTTP transfer alongside the API, so the session id travels in the query string.
	// The Go binding keeps its own session private, so obtain one of our own.
	sid := rawLogin(url, user, password)
	// Take the sections the host marks default-checked, as XenCenter's dialog does: asking for every
	// section can mean gigabytes (VM memory dumps, every log) and a long wait while the host builds it.
	whole := fetchStatusReport(url, sid, defaults)
	fmt.Printf("default sections (%d of %d): %d bytes\n", len(defaults), len(keys), whole)

	// Pick a real, small section from the host's own catalogue rather than assuming a name: the
	// catalogue is server-defined (xen-bugtool's own --capabilities output), not a fixed client
	// list, and "xenserver-config" isn't one of the real keys any host actually publishes.
	subsetKey := keys[0]
	for _, k := range keys {
		if k == "firstboot" || k == "network-status" {
			subsetKey = k
			break
		}
	}
	subset := fetchStatusReport(url, sid, []string{subsetKey})
	fmt.Printf("%s only:   %d bytes\n", subsetKey, subset)
	if subset >= whole {
		fmt.Println("  ERROR: selecting fewer sections did not produce a smaller bundle")
	}

	fmt.Println("OK: server-status-report")
}

// fetchStatusReport downloads the bundle for the given capability keys (a tar archive) to a temp file,
// streaming it - a report can be large - and returns its size. This example then deletes it; you'd keep it.
func fetchStatusReport(url, sid string, entries []string) int {
	resp, err := insecureClient().Get(fmt.Sprintf("%s/system-status?session_id=%s&output=tar&entries=%s",
		url, sid, strings.Join(entries, ",")))
	check(err)
	defer resp.Body.Close()

	temp, err := os.CreateTemp("", "sdk-example-status-*.tar")
	check(err)
	path := temp.Name()
	defer os.Remove(path)

	written, err := io.Copy(temp, resp.Body)
	check(err)
	temp.Close()
	return int(written)
}
