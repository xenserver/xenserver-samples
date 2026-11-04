# Rotate the pool secret.
#
# Rotate the shared secret that authenticates pool members to each other.
#
# Run it:
#   ./workflows.sh rotate-pool-secret https://xenserver root "$password"

rotate_pool_secret() {
    echo "Pool:           $(xe pool-list params=name-label --minimal)"
    # xapi checks its own preconditions before rotating - HA must be disabled, every host must be live, no
    # rolling pool upgrade may be in progress, and the pool must be licensed for it - and xe already prints
    # a clear explanation of whichever one failed, so report that instead of letting the raw failure abort
    # the script. A pool-wide operation; existing sessions survive it.
    if err=$(xe pool-secret-rotate 2>&1); then
        echo "Rotated. Still connected: $(count_csv "$(xe pool-list --minimal)")"
    else
        echo "Could not rotate the pool secret: $err"
    fi
    echo "OK: rotate-pool-secret"
}
