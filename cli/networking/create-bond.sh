# Create a NIC bond.
#
# Bond two spare network interfaces onto a new network for redundancy and throughput, read the bond back, then
# dissolve it.
#
# Run it:
#   ./workflows.sh create-bond https://xenserver root "$password"

create_bond() {
    # NOT `host`: that is the script-level variable the xe() wrapper passes to -s, and shadowing it
    # replaces the server address with a uuid, after which every call fails with "No hostname was
    # specified" and the cause is nowhere near the symptom.
    local host_uuid spares network bond master devices p
    host_uuid=$(first_csv "$(remote_xe host-list --minimal)")

    # Pick up any NIC racked since the host booted; without it a card added a moment ago is not there
    # to bond.
    remote_xe pif-scan host-uuid=$host_uuid

    # Spare NICs only. A bond that includes the management interface moves the management address onto
    # the bond master - on a real host that is how you lose the connection you are working over.
    spares=$(remote_xe pif-list host-uuid="$host_uuid" management=false physical=true --minimal)
    if [ "$(count_csv "$spares")" -lt 2 ]; then
        echo "$(remote_xe host-param-get uuid=$host_uuid param-name=name-label) has $(count_csv "$spares") spare NIC(s); a bond needs two that aren't the management interface" >&2
        return 1
    fi
    spares="$(first_csv "$spares"),$(nth_csv "$spares" 2)"
    devices=""
    for p in $(each_csv "$spares"); do
        devices="${devices:+$devices, }$(remote_xe pif-list uuid=$p params=device --minimal)"
    done
    echo "Bonding:      $devices"

    network=$(remote_xe network-create name-label=sdk-example-bond)
    bond=$(remote_xe bond-create network-uuid="$network" pif-uuids="$spares" mode=balance-slb)
    master=$(remote_xe bond-list uuid="$bond" params=master --minimal)
    echo "Bond master:  $(remote_xe pif-list uuid="$master" params=device --minimal)"
    echo "Mode:         $(remote_xe bond-list uuid="$bond" params=mode --minimal)"

    remote_xe bond-destroy uuid="$bond"
    remote_xe network-destroy uuid="$network"
    echo "Bonds left:   $(count_csv "$(remote_xe bond-list --minimal)")"
    ok create-bond
}
