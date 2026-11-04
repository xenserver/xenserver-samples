# Configure host storage.
#
# Set a host's iSCSI initiator name and turn on storage multipathing, then restore both.
#
# Run it:
#   ./workflows.sh configure-host-storage https://xenserver root "$password"

configure_host_storage() {
    pool=$(first_csv "$(xe pool-list --minimal)")
    host_uuid=$(xe pool-param-get uuid=$pool param-name=master)
    hname=$(xe host-param-get uuid=$host_uuid param-name=name-label)

    before_iqn=$(xe host-param-get uuid=$host_uuid param-name=iscsi_iqn)
    before_multipathing=$(xe host-param-get uuid=$host_uuid param-name=multipathing)
    echo "$hname: iSCSI IQN '$before_iqn', multipathing $before_multipathing"

    xe host-param-set uuid=$host_uuid iscsi_iqn="iqn.2026-01.com.example:$hname"
    xe host-param-set uuid=$host_uuid multipathing=true
    echo "  IQN now:      $(xe host-param-get uuid=$host_uuid param-name=iscsi_iqn)"
    echo "  multipathing: $(xe host-param-get uuid=$host_uuid param-name=multipathing)"

    # host-param-set refuses an empty iscsi_iqn (INVALID_VALUE) - only restore it if this host actually had
    # one set before; a host that never had an IQN configured can't be "restored" to empty.
    [ -n "$before_iqn" ] && xe host-param-set uuid=$host_uuid iscsi_iqn="$before_iqn"
    xe host-param-set uuid=$host_uuid multipathing=$before_multipathing
    echo "  restored"
    echo "OK: configure-host-storage"
}
