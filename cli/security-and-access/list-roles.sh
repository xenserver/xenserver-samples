# List RBAC roles.
#
# Enumerate the pool's role-based access control (RBAC) roles — the roles that can be granted to users.
#
# Run it:
#   ./workflows.sh list-roles https://xenserver root "$password"

list_roles() {
    # role-list shows the roles a user can be granted, not the permissions they are made of. Its field
    # is `name`: a role has no name-label, and asking for one prints nothing.
    echo "Roles: $(xe role-list params=name --minimal)"
    echo "OK: list-roles"
}
