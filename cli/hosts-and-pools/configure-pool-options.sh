# Configure pool options.
#
# Read and change the pool-wide options that govern how it behaves — live patching, IGMP snooping and
# memory-migration compression — then put them back.
#
# Run it:
#   ./workflows.sh configure-pool-options https://xenserver root "$password"

configure_pool_options() {
    pool=$(first_csv "$(remote_xe pool-list --minimal)")
    live_patching=$(remote_xe pool-param-get uuid=$pool param-name=live-patching-disabled)
    igmp=$(remote_xe pool-param-get uuid=$pool param-name=igmp-snooping-enabled)
    migration_compression=$(remote_xe pool-param-get uuid=$pool param-name=migration-compression)
    printf '  %-22s %s\n' "live patching disabled" "$live_patching"
    printf '  %-22s %s\n' "IGMP snooping" "$igmp"
    printf '  %-22s %s\n' "migration compression" "$migration_compression"

    # Live patching applies host updates without a reboot; disabling it forces the reboot.
    remote_xe pool-param-set uuid=$pool live-patching-disabled=$(negate "$live_patching")
    # IGMP snooping keeps multicast off ports that did not ask for it.
    remote_xe pool-param-set uuid=$pool igmp-snooping-enabled=$(negate "$igmp")
    # Compression trades CPU for bandwidth when a VM's memory is moved between hosts.
    remote_xe pool-param-set uuid=$pool migration-compression=$(negate "$migration_compression")

    echo "after changing:"
    printf '  %-22s %s\n' "live patching disabled" "$(remote_xe pool-param-get uuid=$pool param-name=live-patching-disabled)"
    printf '  %-22s %s\n' "IGMP snooping" "$(remote_xe pool-param-get uuid=$pool param-name=igmp-snooping-enabled)"
    printf '  %-22s %s\n' "migration compression" "$(remote_xe pool-param-get uuid=$pool param-name=migration-compression)"

    remote_xe pool-param-set uuid=$pool live-patching-disabled=$live_patching
    remote_xe pool-param-set uuid=$pool igmp-snooping-enabled=$igmp
    remote_xe pool-param-set uuid=$pool migration-compression=$migration_compression
    echo "  restored"
    ok configure-pool-options
}

# The opposite of a "true"/"false" string, for toggling a boolean field and restoring it.
negate() { [ "$1" = "true" ] && echo false || echo true; }
