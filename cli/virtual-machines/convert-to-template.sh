# Convert a VM to a template.
#
# Turn a VM into a reusable custom template. This is a one-way operation.
#
# Run it:
#   ./workflows.sh convert-to-template https://xenserver root "$password"
#
# Optional key=value arguments (default):
#   template_name (Rocky Linux 8)

convert_to_template() {
    local template=$(param template_name "Rocky Linux 8")
    vm=$(xe vm-install template="$template" new-name-label=xe-example-totemplate sr-uuid=$(shared_sr))
    echo "is-a-template after install: $(xe vm-param-get uuid=$vm param-name=is-a-template)"
    xe vm-param-set uuid=$vm is-a-template=true   # one-way operation
    echo "is-a-template after convert: $(xe vm-param-get uuid=$vm param-name=is-a-template)"
    # It is a template now, so template-uninstall removes it and the disks it owns.
    xe template-uninstall template-uuid=$vm force=true
    echo "OK: convert-to-template"
}
