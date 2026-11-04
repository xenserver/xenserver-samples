# Configure console access.
#
# Tighten how consoles and management traffic may be used: idle timeouts for the pool's own consoles and for
# VM consoles, one session at a time, and refusing plain HTTP.
#
# Run it:
#   ./workflows.sh configure-console-access https://xenserver root "$password"

configure_console_access() {
    # NOT `host`: that is the script-level variable the xe() wrapper passes to -s.
    pool=$(first_csv "$(xe pool-list --minimal)")
    host_uuid=$(xe pool-param-get uuid=$pool param-name=master)

    # NB: https-only and the pool console-idle-timeout are set but never read back. The generated SDK
    # bindings have a setter and no getter for both, so the other languages cannot show them - and these
    # samples are meant to read the same across all seven.
    printf '  %-26s %ss\n' "VM console idle timeout" "$(xe pool-param-get uuid=$pool param-name=vm-console-idle-timeout)"
    printf '  %-26s %s\n' "limit console sessions" "$(xe pool-param-get uuid=$pool param-name=limit-console-sessions)"
    printf '  %-26s %ss\n' "host console idle timeout" "$(xe host-param-get uuid=$host_uuid param-name=console-idle-timeout)"

    # Ten minutes of inactivity, one console session at a time, and no plain HTTP.
    xe pool-param-set uuid=$pool console-idle-timeout=600
    xe pool-param-set uuid=$pool vm-console-idle-timeout=600
    xe pool-param-set uuid=$pool limit-console-sessions=true
    xe host-param-set uuid=$host_uuid console-idle-timeout=300
    xe pool-param-set uuid=$pool https-only=true

    echo "after tightening:"
    printf '  %-26s %ss\n' "VM console idle timeout" "$(xe pool-param-get uuid=$pool param-name=vm-console-idle-timeout)"
    printf '  %-26s %s\n' "limit console sessions" "$(xe pool-param-get uuid=$pool param-name=limit-console-sessions)"
    printf '  %-26s %ss\n' "host console idle timeout" "$(xe host-param-get uuid=$host_uuid param-name=console-idle-timeout)"

    xe pool-param-set uuid=$pool https-only=false
    xe pool-param-set uuid=$pool console-idle-timeout=0
    xe pool-param-set uuid=$pool vm-console-idle-timeout=0
    xe pool-param-set uuid=$pool limit-console-sessions=false
    xe host-param-set uuid=$host_uuid console-idle-timeout=0
    echo "  restored"
    echo "OK: configure-console-access"
}
