# Create an iSCSI SR.
#
# Connect a storage repository to a LUN on an iSCSI target, discovering the target's IQNs and then the LUNs
# behind one. Creating the SR formats the LUN, and a shared array offers many targets, so name yours with
# target_iqn; if the target behind it offers more than one LUN, name yours with scsi_id too.
#
# Run it:
#   ./workflows.sh create-iscsi-sr https://xenserver root "$password"
#
# Optional key=value arguments (default):
#   target (192.0.2.30)
#   target_iqn ("")
#   scsi_id (360a980004265656d5f4a2d63764e5734)
#   port ("")
#   chap_user ("")
#   chap_password ("")
#   sr_name (xe-example-iscsi)

# Discover the IQN and the LUN rather than hard-coding a target: a device-config that's missing a piece
# makes the backend fail on purpose, and the failure carries an XML fragment listing what it needs next.
# sr-create formats the chosen LUN - this is destructive, so pick carefully on a real target: pass
# target_iqn to name yours (see choose_target_iqn), and scsi_id too if more than one LUN is offered
# behind it (see choose_lun). Before creating, this probes the chosen LUN itself to make sure it is not
# already in use by another SR - formatting over one would destroy it.
#
# The CHAP password (if any) travels as a Secret, not plaintext device-config, as create_smb_sr already
# does for its share password.
create_iscsi_sr() {
    local target target_iqn scsi_wanted port chap_user chap_password sr_name h xml
    local scsi_id lun lun_id existing_xml uuid
    local -a dc
    target=$(param target "192.0.2.30")
    target_iqn=$(param target_iqn "")
    scsi_wanted=$(param scsi_id "360a980004265656d5f4a2d63764e5734")
    port=$(param port "")
    chap_user=$(param chap_user "")
    chap_password=$(param chap_password "")
    sr_name=$(param sr_name "xe-example-iscsi")
    h=$(first_host)

    dc=(device-config:target="$target")
    [ -n "$port" ] && dc+=(device-config:port="$port")
    # secret (not local: the EXIT trap below reads it after this function has returned).
    secret=""
    if [ -n "$chap_user" ]; then
        secret=$(xe secret-create value="$chap_password")
        trap 'xe secret-destroy uuid=$secret >/dev/null 2>&1' EXIT
        dc+=(device-config:chapuser="$chap_user" device-config:chappassword_secret="$secret")
    fi

    # First failing probe: target only -> the backend lists the IQNs it offers.
    xml=$(probe_for_failure lvmoiscsi host-uuid="$h" "${dc[@]}")
    target_iqn=$(choose_target_iqn "$xml" "$target" "$target_iqn")
    echo "Discovered IQN: $target_iqn"
    dc+=(device-config:targetIQN="$target_iqn")

    # Second failing probe: +targetIQN -> the backend lists the LUNs behind it.
    xml=$(probe_for_failure lvmoiscsi host-uuid="$h" "${dc[@]}")
    lun=$(choose_lun "$xml" "$scsi_wanted")
    scsi_id=$(xml_tag_text "$lun" SCSIid)
    lun_id=$(xml_tag_text "$lun" LUNid); lun_id=${lun_id:-0}
    echo "Discovered LUN $lun_id (SCSIid $scsi_id)"
    dc+=(device-config:SCSIid="$scsi_id" device-config:LUNid="$lun_id")

    # The device-config is now complete enough to create from - which means it is also complete enough to
    # probe the LUN itself: an <SR> in the answer means one is already there, and sr-create would format
    # it. Reattach that SR rather than destroying it.
    existing_xml=$(xe sr-probe type=lvmoiscsi "${dc[@]}")
    if uuid=$(xml_tag_text "$existing_xml" UUID); then
        echo "LUN $scsi_id already holds SR $uuid; creating an SR here would format it - reattach the" \
             "existing SR instead of creating a new one" >&2
        return 1
    fi

    sr=$(xe sr-create host-uuid="$h" type=lvmoiscsi name-label="$sr_name" shared=true "${dc[@]}")
    echo "Created iSCSI SR: $sr ($(( $(xe sr-param-get uuid=$sr param-name=physical-size) / 1024 / 1024 / 1024 )) GiB)"
    # Tidy up: this example created the SR, so destroy it - a forgotten SR would stay on the LUN.
    # SR.destroy needs it detached from every host first.
    for pbd in $(each_csv "$(xe pbd-list sr-uuid=$sr currently-attached=true --minimal)"); do
        xe pbd-unplug uuid=$pbd
    done
    xe sr-destroy uuid=$sr
    if [ -n "$secret" ]; then
        xe secret-destroy uuid=$secret
        trap - EXIT
        secret=""
    fi
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

# Pick the LUN behind the chosen IQN: the caller's SCSIid, if named (it must be one on offer), else the one
# LUN, if that target offers only one. Choose a LUN automatically only when exactly one is on offer, and
# otherwise make the caller choose - picking blindly on a shared target risks formatting someone else's
# disk. Echoes the chosen <LUN>...</LUN> fragment.
choose_lun() {
    local xml=$1 wanted=$2 rest=$xml block scsi_id
    local -a blocks=()
    while [[ $rest == *"<LUN>"* ]]; do
        block=${rest#*<LUN>}; rest=${block#*</LUN>}; block="<LUN>${block%%</LUN>*}"
        blocks+=("$block")
    done
    if [ -n "$wanted" ]; then
        for block in "${blocks[@]}"; do
            scsi_id=$(xml_tag_text "$block" SCSIid)
            if [ "$scsi_id" = "$wanted" ]; then echo "$block"; return 0; fi
        done
        local offered="" sep=""
        for block in "${blocks[@]}"; do offered+="$sep$(xml_tag_text "$block" SCSIid)"; sep=", "; done
        echo "target does not offer a LUN with SCSIid $wanted; offered: $offered" >&2
        return 1
    fi
    if [ "${#blocks[@]}" -eq 1 ]; then echo "${blocks[0]}"; return 0; fi
    local offered="" sep=""
    for block in "${blocks[@]}"; do
        offered+="$sep$(xml_tag_text "$block" SCSIid) ($(xml_tag_text "$block" size) bytes)"; sep=", "
    done
    echo "target offers ${#blocks[@]} LUNs; name one with scsi_id: $offered" >&2
    return 1
}
