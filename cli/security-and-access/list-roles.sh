# List RBAC roles.
#
# Enumerate the pool's role-based access control (RBAC) roles — the roles that can be granted to users.
#
# Run it:
#   ./workflows.sh list-roles https://xenserver root "$password"

list_roles() {
    # role-list shows the roles a user can be granted, not the permissions they are made of. Its field
    # is `name`: a role has no name-label, and asking for one prints nothing.
    local roles first
    roles=$(xe role-list params=name --minimal)
    # Sorted, and at most eight, as the other languages print them.
    first=$(each_csv "$roles" | sort | head -n 8)
    echo "Roles ($(count_csv "$roles")): ${first//$'\n'/, }"
    ok list-roles
}
