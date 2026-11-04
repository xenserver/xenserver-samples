# Configure updates for an air-gapped pool.
#
# Switch a pool with no internet access to offline updates: make an update bundle repository the pool's
# only repository, upload an update bundle (.xsbundle) to it if you have one, list the updates it makes
# available, then tidy up.
#
# Run it:
#   ./workflows.sh configure-offline-updates https://xenserver root "$password" bundle_path=XS9-update.xsbundle
#
# Optional key=value arguments (default):
#   bundle_path ("")

# A pool that cannot reach the CDN takes its updates from a bundle you download elsewhere. The pool needs a
# repository of the bundle kind (it can have only one: introducing a second fails, so use the existing
# one), and it must be the pool's only enabled repository. pool-sync-bundle uploads the bundle to the
# coordinator, which unpacks and checks it; xe waits for that to finish. host-apply-updates then applies it
# (see apply-update). Without bundle_path this only switches the channel and back.
configure_offline_updates() {
    local bundle_path pool before repo existing
    bundle_path=$(param bundle_path "")
    pool=$(xe pool-list --minimal)

    # Remember the pool's own repositories, to put them back afterwards. A set reads back "a; b".
    before=$(xe pool-param-get uuid=$pool param-name=repositories)
    existing=$(xe repository-list origin=bundle --minimal)
    if [ -n "$existing" ]; then
        repo=$(first_csv "$existing")
    else
        repo=$(xe repository-introduce-bundle name-label=sdk-example-offline \
            name-description="Updates from uploaded bundles")
    fi
    xe pool-param-set uuid=$pool repositories=$repo
    echo "Pool repositories: $(xe repository-param-get uuid=$repo param-name=name-label)"

    if [ -n "$bundle_path" ]; then
        xe pool-sync-bundle filename="$bundle_path"
        echo "Uploaded $(basename "$bundle_path")"
    else
        echo "No bundle given: pass bundle_path to upload one"
    fi

    # Forgetting a repository the pool still has enabled fails: restore the pool's own first.
    xe pool-param-set uuid=$pool repositories="$(set_to_csv "$before")"
    [ -n "$existing" ] || xe repository-forget uuid=$repo
    echo "OK: configure-offline-updates"
}
