# Configure updates (CDN).
#
# Point the pool at a CDN update repository and turn on automatic update sync: register a repository, set it
# as the pool's repository, enable update sync, read it back, then tidy up.
#
# Run it:
#   ./workflows.sh configure-updates https://xenserver root "$password"
#
# Optional key=value arguments (default):
#   repo_url (https://repo.ops.xenserver.com/xs9)
#   source_url (https://repo-src.ops.xenserver.com/xs9)

configure_updates() {
    local repo_url source_url repos repo_list names pool before
    repo_url=$(param repo_url "https://repo.ops.xenserver.com/xs9")
    source_url=$(param source_url "https://repo-src.ops.xenserver.com/xs9")
    pool=$(xe pool-list --minimal)
    repos=$(introduce_update_repositories "$repo_url" "$source_url")
    repo_list="" names=""
    for r in $repos; do
        repo_list="${repo_list:+$repo_list,}$r"
        names="${names:+$names, }$(xe repository-param-get uuid=$r param-name=name-label)"
    done
    echo "Introduced repositories: $names"

    # Remember the pool's own repositories, to put them back afterwards. A set reads back "a; b" and is
    # set as "a,b".
    before=$(xe pool-param-get uuid=$pool param-name=repositories)
    xe pool-param-set uuid=$pool repositories=$repo_list
    # The pool's update-sync-enabled is read-only to param-set; xe switches it with its own command.
    xe pool-set-update-sync-enabled value=true
    echo "Pool repositories: $(count_csv "$repo_list"); auto-sync enabled: $(xe pool-param-get uuid=$pool param-name=update-sync-enabled)"

    # Tidy up so the example is repeatable.
    xe pool-set-update-sync-enabled value=false
    xe pool-param-set uuid=$pool repositories="${before//; /,}"
    for r in $repos; do xe repository-forget uuid=$r; done
    echo "OK: configure-updates"
}
