# Tag the pool.
#
# Add and remove a tag on the pool itself, showing that tags apply to the pool, not just VMs and hosts.
#
# Run it:
#   ./workflows.sh pool-tags https://xenserver root "$password"

pool_tags() {
    pool=$(remote_xe pool-list --minimal)
    remote_xe pool-param-add uuid=$pool param-name=tags param-key=sdk-managed
    echo "Pool tags: $(remote_xe pool-param-get uuid=$pool param-name=tags)"
    remote_xe pool-param-remove uuid=$pool param-name=tags param-key=sdk-managed
    ok pool-tags
}
