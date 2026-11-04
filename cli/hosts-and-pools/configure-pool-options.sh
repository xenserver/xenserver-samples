# Configure pool options.
#
# Read and change the pool-wide options that govern how it behaves — live patching, IGMP snooping and
# memory-migration compression — then put them back.
#
# Run it:
#   ./workflows.sh configure-pool-options https://xenserver root "$password"

configure_pool_options() {
    pool=$(first_csv "$(xe pool-list --minimal)")
    live_patching=$(xe pool-param-get uuid=$pool param-name=live-patching-disabled)
    igmp=$(xe pool-param-get uuid=$pool param-name=igmp-snooping-enabled)
    migration_compression=$(xe pool-param-get uuid=$pool param-name=migration-compression)
    printf '  %-22s %s\n' "live patching disabled" "$live_patching"
    printf '  %-22s %s\n' "IGMP snooping" "$igmp"
    printf '  %-22s %s\n' "migration compression" "$migration_compression"

    # Live patching applies host updates without a reboot; disabling it forces the reboot.
    xe pool-param-set uuid=$pool live-patching-disabled=$(negate "$live_patching")
    # IGMP snooping keeps multicast off ports that did not ask for it.
    xe pool-param-set uuid=$pool igmp-snooping-enabled=$(negate "$igmp")
    # Compression trades CPU for bandwidth when a VM's memory is moved between hosts.
    xe pool-param-set uuid=$pool migration-compression=$(negate "$migration_compression")

    echo "after changing:"
    printf '  %-22s %s\n' "live patching disabled" "$(xe pool-param-get uuid=$pool param-name=live-patching-disabled)"
    printf '  %-22s %s\n' "IGMP snooping" "$(xe pool-param-get uuid=$pool param-name=igmp-snooping-enabled)"
    printf '  %-22s %s\n' "migration compression" "$(xe pool-param-get uuid=$pool param-name=migration-compression)"

    xe pool-param-set uuid=$pool live-patching-disabled=$live_patching
    xe pool-param-set uuid=$pool igmp-snooping-enabled=$igmp
    xe pool-param-set uuid=$pool migration-compression=$migration_compression
    echo "  restored"
    echo "OK: configure-pool-options"
}

# The opposite of a "true"/"false" string, for toggling a boolean field and restoring it.
negate() { [ "$1" = "true" ] && echo false || echo true; }
