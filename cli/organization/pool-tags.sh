# Tag the pool.
#
# Add and remove a tag on the pool itself, showing that tags apply to the pool, not just VMs and hosts.
#
# Run it:
#   ./workflows.sh pool-tags https://xenserver root "$password"

pool_tags() {
    pool=$(xe pool-list --minimal)
    xe pool-param-add uuid=$pool param-name=tags param-key=xe-managed
    echo "Pool tags: $(xe pool-param-get uuid=$pool param-name=tags)"
    xe pool-param-remove uuid=$pool param-name=tags param-key=xe-managed
    echo "OK: pool-tags"
}
