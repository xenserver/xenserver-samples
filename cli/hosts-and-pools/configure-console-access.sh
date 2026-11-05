# Configure console access.
#
# Tighten how consoles and management traffic may be used: idle timeouts for the pool's own consoles and for
# VM consoles, one session at a time, and refusing plain HTTP. Restore every value it changed afterwards.
#
# Run it:
#   ./workflows.sh configure-console-access https://xenserver root "$password"

configure_console_access() {
    # NOT `host`: that is the script-level variable the xe() wrapper passes to -s.
    pool=$(first_csv "$(xe pool-list --minimal)")
    host_uuid=$(xe pool-param-get uuid=$pool param-name=master)

    # NB: pool https-only and pool console-idle-timeout are set below but never read back AT THE POOL
    # LEVEL. The generated SDK bindings have a setter and no getter for either there, because both are
    # really fan-outs that set the equivalent host field on every host rather than pool fields of their
    # own. host https-only and host console-idle-timeout ARE ordinary readable fields, so read this host's
    # values back instead, to show the effect and to know what to restore.
    before_vm_console_idle_timeout=$(xe pool-param-get uuid=$pool param-name=vm-console-idle-timeout)
    before_limit_console_sessions=$(xe pool-param-get uuid=$pool param-name=limit-console-sessions)
    before_host_console_idle_timeout=$(xe host-param-get uuid=$host_uuid param-name=console-idle-timeout)
    before_host_https_only=$(xe host-param-get uuid=$host_uuid param-name=https-only)
    printf '  %-26s %ss\n' "VM console idle timeout" "$before_vm_console_idle_timeout"
    printf '  %-26s %s\n' "limit console sessions" "$before_limit_console_sessions"
    printf '  %-26s %ss\n' "host console idle timeout" "$before_host_console_idle_timeout"
    printf '  %-26s %s\n' "host https only" "$before_host_https_only"

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
    printf '  %-26s %s\n' "host https only" "$(xe host-param-get uuid=$host_uuid param-name=https-only)"

    xe pool-param-set uuid=$pool https-only=$before_host_https_only
    xe pool-param-set uuid=$pool console-idle-timeout=$before_host_console_idle_timeout
    xe pool-param-set uuid=$pool vm-console-idle-timeout=$before_vm_console_idle_timeout
    xe pool-param-set uuid=$pool limit-console-sessions=$before_limit_console_sessions
    xe host-param-set uuid=$host_uuid console-idle-timeout=$before_host_console_idle_timeout
    echo "  restored"
    echo "OK: configure-console-access"
}
