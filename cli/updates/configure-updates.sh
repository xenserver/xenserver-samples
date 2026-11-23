# Configure updates (CDN).
#
# Point the pool at a CDN update repository and turn on automatic update sync: register the repository,
# set it as the pool's repository, enable update sync, read it back, then tidy up.
#
# Run it:
#   ./workflows.sh configure-updates https://xenserver root "$password"
#
# Optional key=value arguments (default):
#   repo_url (https://repo.ops.xenserver.com/xs9)
#   source_url (https://repo-src.ops.xenserver.com/xs9)

configure_updates() {
    local repo_url source_url repo name pool before
    repo_url=$(param repo_url "https://repo.ops.xenserver.com/xs9")
    source_url=$(param source_url "https://repo-src.ops.xenserver.com/xs9")
    pool=$(remote_xe pool-list --minimal)
    repo=$(introduce_update_repository "$repo_url" "$source_url")
    name=$(remote_xe repository-param-get uuid=$repo param-name=name-label)
    echo "Introduced repository: $name"

    # Remember the pool's own repositories, to put them back afterwards. A set reads back "a; b" and is
    # set as "a,b".
    before=$(remote_xe pool-param-get uuid=$pool param-name=repositories)
    remote_xe pool-param-set uuid=$pool repositories=$repo
    # The pool's update-sync-enabled is read-only to param-set; xe switches it with its own command.
    remote_xe pool-set-update-sync-enabled value=true
    echo "Pool repository: $name; auto-sync enabled: $(remote_xe pool-param-get uuid=$pool param-name=update-sync-enabled)"

    # Tidy up so the example is repeatable.
    remote_xe pool-set-update-sync-enabled value=false
    remote_xe pool-param-set uuid=$pool repositories="${before//; /,}"
    remote_xe repository-forget uuid=$repo
    ok configure-updates
}
