package testGoSDK

import (
	"fmt"
	"testing"
	"time"

	xenapi "github.com/xenserver/xenserver-samples/go/goSDK"
)

var eventTypes []string
var maxTries = 3
var timeout = 10.0
var token = ""

func TestEventFrom(t *testing.T) {
	eventTypes = append(eventTypes, "*")
	for i := 0; i < maxTries; i++ {
		eventBatch, err := xenapi.Event.From(session, eventTypes, token, timeout)
		if err != nil {
			t.Log(err)
			t.Fail()
			return
		}
		token = eventBatch.Token
		t.Log(fmt.Sprintf("Poll %d out of %d: %d event(s) received", i, maxTries, len(eventBatch.Events)))
		for _, event := range eventBatch.Events {
			t.Log(fmt.Sprintf("%s %d %s %s", event.Class, event.ID, event.Operation, event.Ref))
		}

		t.Log("Waiting 5 seconds before next poll...")
		time.Sleep(time.Duration(5) * time.Second)
	}
}
