# List templates.
#
# Enumerate the pool's VM templates, both built-in and custom.
#
# Run it:
#   ./workflows.sh list-templates https://xenserver root "$password"

list_templates() {
    local t name
    # template-list leaves out snapshots, which are templates too. A built-in template carries
    # other-config:default_template.
    echo "Templates ($(count_csv "$(remote_xe template-list --minimal)")):"
    for t in $(each_csv "$(remote_xe template-list --minimal)"); do
        name=$(remote_xe template-param-get uuid=$t param-name=name-label)
        if remote_xe_try template-param-get uuid=$t param-name=other-config param-key=default_template >/dev/null 2>&1; then
            printf '%s\t  - %s [built-in]\n' "$name" "$name"
        else
            printf '%s\t  - %s\n' "$name" "$name"
        fi
    done | sort | head -8 | cut -f2-
    ok list-templates
}
