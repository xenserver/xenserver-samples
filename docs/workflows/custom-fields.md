<!-- Generated from workflows.json, the example sources and a run of each example. Edit those, not this file. -->

# Custom fields

Attach and read custom name/value fields on a VM — arbitrary metadata you define, stored on the object.

Workflow `custom-fields`. [All workflows](README.md) · [Connecting](connecting.md)

## C# (.NET)

Source: [`csharp/Organization/CustomFields.cs`](../../csharp/Organization/CustomFields.cs)

```csharp
private const string CustomFieldBaseKey = "XenCenter.CustomFields";
private const string FieldName = "Owner";
private const string FieldKey = CustomFieldBaseKey + "." + FieldName;

/// <summary>
/// Attach and read a custom name/value field on a VM — arbitrary metadata you define. A management
/// client only shows a field once it has been DEFINED for the pool; the value on the object is a
/// separate step. This sample does both.
/// </summary>
/// <example>
/// <code>
/// Workflows.CustomFields("https://xenserver", "root", password, "web-01");
/// </code>
/// </example>
public static void CustomFields(string url, string user, string password, string vmName)
{
    var session = Connect(url, user, password);
    var vm = VmByName(session, vmName);
    var pool = Pool.get_all(session).First().opaque_ref;

    // The pool's custom field DEFINITIONS (name and type, String or Date) live in a small XML document in
    // pool.gui_config["XenCenter.CustomFields"] (the key keeps its historical name); a client shows no
    // field without one, no matter what value an object carries under XenCenter.CustomFields.<name>.
    var previousXml = Pool.get_gui_config(session, pool).GetValueOrDefault(CustomFieldBaseKey);
    var doc = previousXml != null
        ? XDocument.Parse(previousXml)
        : new XDocument(new XElement("CustomFieldDefinitions"));
    var addedDefinition = doc.Root.Elements("CustomFieldDefinition")
        .All(e => (string)e.Attribute("name") != FieldName);
    if (addedDefinition)
    {
        doc.Root.Add(new XElement("CustomFieldDefinition",
            new XAttribute("name", FieldName), new XAttribute("type", "String")));
        Pool.add_to_gui_config(session, pool, CustomFieldBaseKey, doc.ToString(SaveOptions.DisableFormatting));
    }
    Console.WriteLine($"Field defined: {addedDefinition}");

    // With the field defined, giving it a value on an object is a plain other_config write.
    VM.add_to_other_config(session, vm, FieldKey, "Platform Team");
    Console.WriteLine($"Custom field Owner = {VM.get_other_config(session, vm)[FieldKey]}");

    VM.remove_from_other_config(session, vm, FieldKey);
    if (addedDefinition)
    {
        // Only this sample's own definition is ours to remove, and only by putting back the
        // pool's previous gui_config value exactly (there may be other definitions alongside it).
        if (previousXml == null)
            Pool.remove_from_gui_config(session, pool, CustomFieldBaseKey);
        else
            Pool.add_to_gui_config(session, pool, CustomFieldBaseKey, previousXml);
    }

    Console.WriteLine("OK: custom-fields");
    session.logout();
}
```

<details><summary>Sample output</summary>

```text
Field defined: True
Custom field Owner = Platform Team
OK: custom-fields
```

</details>

## Python

Source: [`python/organization/custom_fields.py`](../../python/organization/custom_fields.py)

```python
"""Custom fields.

Attach and read a custom name/value field on a VM -- arbitrary metadata you define. A management client
only shows a field once it has been DEFINED for the pool; the value on the object is a separate step.
This sample does both.

Run it::

    custom_fields("https://xenserver", "root", password, "web-01")
"""

from xml.etree import ElementTree

from connection import connect
from helpers import vm_by_name

CUSTOM_FIELD_BASE_KEY = "XenCenter.CustomFields"
FIELD_NAME = "Owner"
FIELD_KEY = "%s.%s" % (CUSTOM_FIELD_BASE_KEY, FIELD_NAME)


def custom_fields(url, username, password, vm_name):
    """Define the Owner custom field if it is not defined yet, assign it a value, read it back, then
    tidy up: drop the value always, and the definition only if this sample added it."""
    session = connect(url, username, password)
    vm = vm_by_name(session, vm_name)
    pool = session.xenapi.pool.get_all()[0]

    # The pool's custom field DEFINITIONS (name and type, String or Date) live in a small XML document
    # in pool.gui_config["XenCenter.CustomFields"] (the key keeps its historical name); a client shows
    # no field without one, no matter what value an object carries under XenCenter.CustomFields.<name>.
    previous_xml = session.xenapi.pool.get_gui_config(pool).get(CUSTOM_FIELD_BASE_KEY)
    root = (ElementTree.fromstring(previous_xml) if previous_xml
            else ElementTree.Element("CustomFieldDefinitions"))
    added_definition = all(child.get("name") != FIELD_NAME for child in root)
    if added_definition:
        ElementTree.SubElement(root, "CustomFieldDefinition", {"name": FIELD_NAME, "type": "String"})
        session.xenapi.pool.add_to_gui_config(
            pool, CUSTOM_FIELD_BASE_KEY, ElementTree.tostring(root, encoding="unicode"))
    print("Field defined: %s" % added_definition)

    # With the field defined, giving it a value on an object is a plain other_config write.
    session.xenapi.VM.add_to_other_config(vm, FIELD_KEY, "Platform Team")
    print("Custom field Owner = %s" % session.xenapi.VM.get_other_config(vm)[FIELD_KEY])

    session.xenapi.VM.remove_from_other_config(vm, FIELD_KEY)
    if added_definition:
        # Only this sample's own definition is ours to remove, and only by putting back the pool's
        # previous gui_config value exactly (there may be other definitions alongside it).
        if previous_xml is None:
            session.xenapi.pool.remove_from_gui_config(pool, CUSTOM_FIELD_BASE_KEY)
        else:
            session.xenapi.pool.add_to_gui_config(pool, CUSTOM_FIELD_BASE_KEY, previous_xml)
    print("OK: custom-fields")
    session.xenapi.session.logout()
```

<details><summary>Sample output</summary>

```text
Field defined: True
Custom field Owner = Platform Team
OK: custom-fields
```

</details>

## Java

Source: [`java/src/main/java/com/xenserver/samples/organization/CustomFields.java`](../../java/src/main/java/com/xenserver/samples/organization/CustomFields.java)

```java
package com.xenserver.samples.organization;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.Pool;
import com.xensource.xenapi.Session;
import com.xensource.xenapi.VM;

import org.w3c.dom.Document;
import org.w3c.dom.Element;
import org.w3c.dom.NodeList;

import java.io.StringWriter;
import java.util.Map;

import javax.xml.transform.OutputKeys;
import javax.xml.transform.Transformer;
import javax.xml.transform.TransformerFactory;
import javax.xml.transform.dom.DOMSource;
import javax.xml.transform.stream.StreamResult;

import static com.xenserver.samples.Helpers.parseXml;
import static com.xenserver.samples.Helpers.vmByName;
import static com.xenserver.samples.PoolConnection.connect;

public final class CustomFields {
    private CustomFields() {
    }

    private static final String CUSTOM_FIELD_BASE_KEY = "XenCenter.CustomFields";
    private static final String FIELD_NAME = "Owner";
    private static final String FIELD_KEY = CUSTOM_FIELD_BASE_KEY + "." + FIELD_NAME;

    /**
     * Custom fields.
     *
     * <p>Attach and read a custom name/value field on a VM — arbitrary metadata you define. A
     * management client only shows a field once it has been DEFINED for the pool; the value on the
     * object is a separate step. This sample does both.
     *
     * <p>Run it:
     *
     * <pre>{@code
     * CustomFields.run("https://xenserver", "root", password, "web-01");
     * }</pre>
     */
    public static void run(String url, String user, String password, String vmName) throws Exception {
        Connection conn = connect(url, user, password);
        try {
            VM vm = vmByName(conn, vmName);
            Pool pool = Pool.getAll(conn).iterator().next();

            // The pool's custom field DEFINITIONS (name and type, String or Date) live in a small XML
            // document in pool.gui_config["XenCenter.CustomFields"] (the key keeps its historical
            // name); a client shows no field without one, no matter what value an object carries under
            // XenCenter.CustomFields.<name>.
            Map<String, String> guiConfig = pool.getGuiConfig(conn);
            String previousXml = guiConfig.get(CUSTOM_FIELD_BASE_KEY);
            Document doc = parseXml(previousXml != null ? previousXml : "<CustomFieldDefinitions/>");
            Element root = doc.getDocumentElement();
            boolean addedDefinition = true;
            NodeList existing = root.getElementsByTagName("CustomFieldDefinition");
            for (int i = 0; i < existing.getLength(); i++) {
                if (FIELD_NAME.equals(((Element) existing.item(i)).getAttribute("name"))) {
                    addedDefinition = false;
                    break;
                }
            }
            if (addedDefinition) {
                Element definition = doc.createElement("CustomFieldDefinition");
                definition.setAttribute("name", FIELD_NAME);
                definition.setAttribute("type", "String");
                root.appendChild(definition);
                pool.addToGuiConfig(conn, CUSTOM_FIELD_BASE_KEY, toXmlString(doc));
            }
            System.out.println("Field defined: " + addedDefinition);

            // With the field defined, giving it a value on an object is a plain other_config write.
            vm.addToOtherConfig(conn, FIELD_KEY, "Platform Team");
            System.out.println("Custom field Owner = " + vm.getOtherConfig(conn).get(FIELD_KEY));

            vm.removeFromOtherConfig(conn, FIELD_KEY);
            if (addedDefinition) {
                // Only this sample's own definition is ours to remove, and only by putting back the
                // pool's previous gui_config value exactly (there may be other definitions alongside
                // it).
                if (previousXml != null) {
                    pool.addToGuiConfig(conn, CUSTOM_FIELD_BASE_KEY, previousXml);
                } else {
                    pool.removeFromGuiConfig(conn, CUSTOM_FIELD_BASE_KEY);
                }
            }
            System.out.println("OK: custom-fields");
        } finally {
            Session.logout(conn);
        }
    }

    private static String toXmlString(Document doc) throws Exception {
        Transformer transformer = TransformerFactory.newInstance().newTransformer();
        transformer.setOutputProperty(OutputKeys.OMIT_XML_DECLARATION, "yes");
        StringWriter writer = new StringWriter();
        transformer.transform(new DOMSource(doc), new StreamResult(writer));
        return writer.toString();
    }
}
```

<details><summary>Sample output</summary>

```text
Field defined: true
Custom field Owner = Platform Team
OK: custom-fields
```

</details>

## Go

Source: [`go/custom_fields.go`](../../go/custom_fields.go)

```go
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
```

<details><summary>Sample output</summary>

```text
Field defined: true
Custom field Owner = Platform Team
OK: custom-fields
```

</details>

## PowerShell

Source: [`powershell/Organization/Invoke-CustomFields.ps1`](../../powershell/Organization/Invoke-CustomFields.ps1)

```powershell
function Invoke-CustomFields {
    <#
    .SYNOPSIS
        Custom fields.
    .DESCRIPTION
        Attach and read a custom name/value field on a VM -- arbitrary metadata you define. A management
        client only shows a field once it has been DEFINED for the pool; the value on the object is a
        separate step. This sample does both.
    .EXAMPLE
        Invoke-CustomFields -Url https://xenserver -UserName root -Password $password -VmName 'web-01'
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$UserName,
        [Parameter(Mandatory = $true)][string]$Password,
        [Parameter(Mandatory = $true)][string]$VmName
    )
    $session = Connect-Example -Url $Url -UserName $UserName -Password $Password
    $customFieldBaseKey = "XenCenter.CustomFields"
    $fieldName = "Owner"
    $fieldKey = "$customFieldBaseKey.$fieldName"

    $vm = Get-XenVM -Name $VmName |
        Where-Object { -not $_.is_a_template -and -not $_.is_control_domain } | Select-Object -First 1
    if (-not $vm) { throw "No VM named '$VmName' was found." }
    $pool = Get-XenPool | Select-Object -First 1

    # The pool's custom field DEFINITIONS (name and type, String or Date) live in a small XML document in
    # pool.gui_config["XenCenter.CustomFields"] (the key keeps its historical name); a client shows no
    # field without one, no matter what value an object carries under XenCenter.CustomFields.<name>.
    $previousXml = $pool.gui_config[$customFieldBaseKey]
    [xml]$doc = if ($previousXml) { $previousXml } else { "<CustomFieldDefinitions />" }
    $addedDefinition = -not ($doc.CustomFieldDefinitions.CustomFieldDefinition |
        Where-Object { $_.name -eq $fieldName })
    if ($addedDefinition) {
        $definition = $doc.CreateElement("CustomFieldDefinition")
        $definition.SetAttribute("name", $fieldName)
        $definition.SetAttribute("type", "String")
        [void]$doc.DocumentElement.AppendChild($definition)

        $guiConfig = @{}
        foreach ($k in $pool.gui_config.Keys) { $guiConfig[$k] = $pool.gui_config[$k] }
        $guiConfig[$customFieldBaseKey] = $doc.OuterXml
        $pool | Set-XenPool -GuiConfig $guiConfig
    }
    Write-Host "Field defined: $addedDefinition"

    # With the field defined, giving it a value on an object is a plain other_config write.
    # Set-XenVM -OtherConfig replaces the whole map, so merge the field into a copy; Remove-XenVMProperty
    # -OtherConfig then drops it again by key.
    $oc = @{}
    foreach ($k in $vm.other_config.Keys) { $oc[$k] = $vm.other_config[$k] }
    $oc[$fieldKey] = "Platform Team"
    $vm | Set-XenVM -OtherConfig $oc
    Write-Host "Custom field Owner = $((Get-XenVM -Ref $vm.opaque_ref).other_config[$fieldKey])"

    $vm | Remove-XenVMProperty -OtherConfig $fieldKey
    if ($addedDefinition) {
        # Only this sample's own definition is ours to remove, and only by putting back the pool's
        # previous gui_config value exactly (there may be other definitions alongside it).
        if ($previousXml) {
            $guiConfig = @{}
            foreach ($k in $pool.gui_config.Keys) { $guiConfig[$k] = $pool.gui_config[$k] }
            $guiConfig[$customFieldBaseKey] = $previousXml
            $pool | Set-XenPool -GuiConfig $guiConfig
        } else {
            $pool | Remove-XenPoolProperty -GuiConfig $customFieldBaseKey
        }
    }
    Write-Host "OK: custom-fields"
    $session | Disconnect-XenServer
}
```

<details><summary>Sample output</summary>

```text
Field defined: True
Custom field Owner = Platform Team
OK: custom-fields
```

</details>

## xe CLI

Source: [`cli/organization/custom-fields.sh`](../../cli/organization/custom-fields.sh)

```bash
# Custom fields.
#
# Attach and read a custom name/value field on a VM -- arbitrary metadata you define. A management client only
# shows a field once it has been DEFINED for the pool; the value on the object is a separate step. This sample
# does both.
#
# Run it:
#   ./workflows.sh custom-fields https://xenserver root "$password"

custom_fields() {
    vm=$(vm_uuid web-01)
    pool=$(first_csv "$(xe pool-list --minimal)")
    field_key="XenCenter.CustomFields.Owner"

    # The pool's custom field DEFINITIONS (name and type, String or Date) live in a small XML document in
    # pool.gui-config["XenCenter.CustomFields"] (the key keeps its historical name); a client shows no field
    # without one, no matter what value an object carries under XenCenter.CustomFields.<name>.
    previous_xml=$(xe pool-param-get uuid=$pool param-name=gui-config param-key=XenCenter.CustomFields 2>/dev/null) || true
    added_definition=false
    if [[ "$previous_xml" != *'name="Owner"'* ]]; then
        added_definition=true
        if [ -z "$previous_xml" ]; then
            new_xml='<CustomFieldDefinitions><CustomFieldDefinition name="Owner" type="String" /></CustomFieldDefinitions>'
        else
            new_xml="${previous_xml%</CustomFieldDefinitions>}<CustomFieldDefinition name=\"Owner\" type=\"String\" /></CustomFieldDefinitions>"
        fi
        xe pool-param-set uuid=$pool gui-config:XenCenter.CustomFields="$new_xml"
    fi
    echo "Field defined: $added_definition"

    # With the field defined, giving it a value on an object is a plain other-config write.
    xe vm-param-set uuid=$vm other-config:$field_key="Platform Team"
    echo "Owner = $(xe vm-param-get uuid=$vm param-name=other-config param-key=$field_key)"

    xe vm-param-remove uuid=$vm param-name=other-config param-key=$field_key
    if [ "$added_definition" = true ]; then
        # Only this sample's own definition is ours to remove, and only by putting back the pool's
        # previous gui-config value exactly (there may be other definitions alongside it).
        if [ -z "$previous_xml" ]; then
            xe pool-param-remove uuid=$pool param-name=gui-config param-key=XenCenter.CustomFields
        else
            xe pool-param-set uuid=$pool gui-config:XenCenter.CustomFields="$previous_xml"
        fi
    fi
    echo "OK: custom-fields"
}
```

<details><summary>Sample output</summary>

```text
Field defined: true
Owner = Platform Team
OK: custom-fields
```

</details>
