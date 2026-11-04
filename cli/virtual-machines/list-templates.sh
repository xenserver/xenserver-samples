# List templates.
#
# Enumerate the pool's VM templates, both built-in and custom.
#
# Run it:
#   ./workflows.sh list-templates https://xenserver root "$password"

list_templates() {
    echo "Templates ($(count_csv "$(xe template-list --minimal)")):"
    IFS=, read -ra names <<< "$(xe template-list params=name-label --minimal)"
    printf '%s\n' "${names[@]:0:8}"
    echo "OK: list-templates"
}
