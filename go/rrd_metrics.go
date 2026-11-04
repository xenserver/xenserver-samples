package main

import (
	"encoding/json"
	"fmt"
	"net/http"
	"strconv"
	"strings"
	"time"

	"go/xenapi"
)

// rrdMetrics - Read RRD performance metrics.
//
// Pull recent host performance samples from the RRD archives over the performance-data HTTP API,
// parse the legends and data, and summarise a metric (here the peak PVS Accelerator cache-space
// utilisation per host).
func rrdMetrics(url, user, password string) {
	session := connect(url, user, password)
	defer session.Logout()

	hosts, err := xenapi.Host.GetAllRecords(session)
	check(err)
	nameByUUID := map[string]string{}
	for _, h := range hosts {
		nameByUUID[h.UUID] = h.NameLabel
	}

	// The RRD time-series isn't a XenAPI call; read rrd_updates over HTTP. It needs a session id (the SDK
	// keeps its own private), so obtain one with a small JSON-RPC login. Legends are
	// "AVERAGE:host:<uuid>:<datasource>"; values[] aligns to legend[].
	sid := rawLogin(url, user, password)
	start := time.Now().Unix() - 300
	req, _ := http.NewRequest("GET", fmt.Sprintf("%s/rrd_updates?session_id=%s&host=true&start=%d", url, sid, start), nil)
	req.Header.Set("accept", "application/json")
	resp, err := insecureClient().Do(req)
	check(err)
	defer resp.Body.Close()

	var rrd struct {
		Meta struct {
			Legend []string `json:"legend"`
		} `json:"meta"`
		Data []struct {
			Values []any `json:"values"`
		} `json:"data"`
	}
	check(json.NewDecoder(resp.Body).Decode(&rrd))

	peak := map[string]float64{}
	for _, point := range rrd.Data {
		for k, legend := range rrd.Meta.Legend {
			parts := strings.Split(legend, ":")
			if parts[1] != "host" || parts[3] != "pvsaccelerator_space_utilization" {
				continue
			}
			// A host sends each value as a string ("0.0", or "NaN" for a gap in the series).
			var v float64
			switch x := point.Values[k].(type) {
			case string:
				v, _ = strconv.ParseFloat(x, 64)
			case float64:
				v = x
			}
			if v != v { // NaN: a gap in the series, not a real sample - never let it stick
				continue
			}
			// A plain `v > peak[key]` relies on a zero-valued map default, so a real 0.0 reading
			// (the common, unconfigured-PVS case) would never get inserted and the whole per-host
			// loop would silently print nothing - track presence explicitly instead.
			if cur, ok := peak[parts[2]]; !ok || v > cur {
				peak[parts[2]] = v
			}
		}
	}
	for uuid, p := range peak {
		fmt.Printf("  %s: peak PVS cache utilisation %.0f%%\n", nameByUUID[uuid], p)
	}
	fmt.Println("OK: rrd-metrics")
}
