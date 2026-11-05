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
