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
    vm=$(remote_xe vm-install template="$template" new-name-label=xe-example-totemplate)
    echo "is-a-template after install: $(remote_xe vm-param-get uuid=$vm param-name=is-a-template)"
    remote_xe vm-param-set uuid=$vm is-a-template=true   # one-way operation
    echo "is-a-template after convert: $(remote_xe vm-param-get uuid=$vm param-name=is-a-template)"
    # It is a template now, so template-uninstall removes it and the disks it owns.
    remote_xe template-uninstall template-uuid=$vm force=true
    echo "Cleaned up the example template."
    ok convert-to-template
}
