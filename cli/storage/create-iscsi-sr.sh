# Create an iSCSI SR.
#
# Connect a storage repository to a LUN on an iSCSI target, discovering the target's IQNs and then the LUNs
# behind one, as the New SR wizard does. Creating the SR formats the LUN, and a shared array offers many
# targets, so name yours with target_iqn.
#
# Run it:
#   ./workflows.sh create-iscsi-sr https://xenserver root "$password"
#
# Optional key=value arguments (default):
#   target (192.0.2.30)
#   target_iqn ("")
#   port ("")
#   chap_user ("")
#   chap_password ("")
#   sr_name (xe-example-iscsi)

# Discover the IQN and the LUN the way the New SR wizard does, instead of a hard-coded target: a
# device-config that's missing a piece makes the backend fail on purpose, and the failure carries an XML
# fragment listing what it needs next. sr-create formats the chosen LUN - this is destructive, so
# pick carefully on a real target: pass target_iqn to name yours (see choose_target_iqn).
create_iscsi_sr() {
    local target port chap_user chap_password sr_name h
    local -a dc
    target=$(param target "192.0.2.30")
    target_iqn=$(param target_iqn "")
    port=$(param port "")
    chap_user=$(param chap_user "")
    chap_password=$(param chap_password "")
    sr_name=$(param sr_name "xe-example-iscsi")
    h=$(first_host)

    dc=(device-config:target="$target")
    [ -n "$port" ] && dc+=(device-config:port="$port")
    [ -n "$chap_user" ] && dc+=(device-config:chapuser="$chap_user" device-config:chappassword="$chap_password")

    # First failing probe: target only -> the backend lists the IQNs it offers.
    xml=$(probe_for_failure lvmoiscsi host-uuid="$h" "${dc[@]}")
    target_iqn=$(choose_target_iqn "$xml" "$target" "$target_iqn")
    echo "Discovered IQN: $target_iqn"
    dc+=(device-config:targetIQN="$target_iqn")

    # Second failing probe: +targetIQN -> the backend lists the LUNs behind it.
    xml=$(probe_for_failure lvmoiscsi host-uuid="$h" "${dc[@]}")
    lun=${xml#*<LUN>}; lun="<LUN>${lun%%</LUN>*}"
    scsi_id=$(xml_tag_text "$lun" SCSIid)
    lun_id=$(xml_tag_text "$lun" LUNid); lun_id=${lun_id:-0}
    echo "Discovered LUN $lun_id (SCSIid $scsi_id)"

    sr=$(xe sr-create host-uuid="$h" type=lvmoiscsi name-label="$sr_name" shared=true \
        "${dc[@]}" device-config:SCSIid="$scsi_id" device-config:LUNid="$lun_id")
    echo "Created iSCSI SR: $sr ($(( $(xe sr-param-get uuid=$sr param-name=physical-size) / 1024 / 1024 / 1024 )) GiB)"
    detach_and_forget_sr $sr
    echo "OK: create-iscsi-sr"
}

# Pick the IQN from an iSCSI discovery probe's XML: the caller's, if named (it must be one the target
# offers), else the first. An array usually offers many targets - one per LUN, often belonging to different
# users - so on shared storage always name yours: sr-create formats the LUN behind it.
choose_target_iqn() {
    local rest=$1 target=$2 wanted=$3 first="" iqn
    while [[ $rest == *"<TargetIQN>"* ]]; do
        rest=${rest#*<TargetIQN>}; iqn=${rest%%</TargetIQN>*}
        [ -n "$first" ] || first=$iqn
        if [ -n "$wanted" ] && [ "$iqn" = "$wanted" ]; then echo "$iqn"; return 0; fi
    done
    if [ -n "$wanted" ]; then echo "target $target does not offer IQN $wanted" >&2; return 1; fi
    echo "$first"
}
