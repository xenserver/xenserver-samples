package main

import (
	"encoding/xml"
	"fmt"

	"go/xenapi"
)

const (
	customFieldBaseKey = "XenCenter.CustomFields"
	customFieldName    = "Owner"
	customFieldKey     = customFieldBaseKey + "." + customFieldName
)

type customFieldDefinitions struct {
	XMLName     xml.Name                `xml:"CustomFieldDefinitions"`
	Definitions []customFieldDefinition `xml:"CustomFieldDefinition"`
}

type customFieldDefinition struct {
	Name string `xml:"name,attr"`
	Type string `xml:"type,attr"`
}

// customFields - Custom fields.
//
// Attach and read a custom name/value field on a VM — arbitrary metadata you define. A management client
// only shows a field once it has been DEFINED for the pool; the value on the object is a separate step.
// This sample does both.
//
// Run it:
//
//	customFields("https://xenserver", "root", password, "web-01")
func customFields(url, user, password, vmName string) {
	session := connect(url, user, password)
	defer session.Logout()
	vm := vmByName(session, vmName)
	pools, err := xenapi.Pool.GetAll(session)
	check(err)
	pool := pools[0]

	// The pool's custom field DEFINITIONS (name and type, String or Date) live in a small XML document in
	// pool.gui_config["XenCenter.CustomFields"] (the key keeps its historical name); a client shows no field
	// without one, no matter what value an object carries under XenCenter.CustomFields.<name>.
	guiConfig, err := xenapi.Pool.GetGuiConfig(session, pool)
	check(err)
	previousXML, hadPreviousXML := guiConfig[customFieldBaseKey]
	var defs customFieldDefinitions
	if hadPreviousXML {
		check(xml.Unmarshal([]byte(previousXML), &defs))
	}
	addedDefinition := true
	for _, d := range defs.Definitions {
		if d.Name == customFieldName {
			addedDefinition = false
			break
		}
	}
	if addedDefinition {
		defs.Definitions = append(defs.Definitions, customFieldDefinition{Name: customFieldName, Type: "String"})
		newXML, err := xml.Marshal(defs)
		check(err)
		check(xenapi.Pool.AddToGuiConfig(session, pool, customFieldBaseKey, string(newXML)))
	}
	fmt.Printf("Field defined: %t\n", addedDefinition)

	// With the field defined, giving it a value on an object is a plain other_config write.
	check(xenapi.VM.AddToOtherConfig(session, vm, customFieldKey, "Platform Team"))
	oc, err := xenapi.VM.GetOtherConfig(session, vm)
	check(err)
	fmt.Printf("Custom field Owner = %s\n", oc[customFieldKey])

	check(xenapi.VM.RemoveFromOtherConfig(session, vm, customFieldKey))
	if addedDefinition {
		// Only this sample's own definition is ours to remove, and only by putting back the pool's
		// previous gui_config value exactly (there may be other definitions alongside it).
		if hadPreviousXML {
			check(xenapi.Pool.AddToGuiConfig(session, pool, customFieldBaseKey, previousXML))
		} else {
			check(xenapi.Pool.RemoveFromGuiConfig(session, pool, customFieldBaseKey))
		}
	}
	fmt.Println("OK: custom-fields")
}
