# Create an HBA SR.
#
# Connect a shared storage repository to a fibre-channel (HBA) LUN: discover the LUNs the host can see with a
# deliberately failing probe, then create the SR by SCSI ID. Creating the SR formats the LUN.
#
# Run it:
#   ./workflows.sh create-hba-sr https://xenserver root "$password"
#
# Optional key=value arguments (default):
#   sr_name (xe-example-hba)
#   scsi_id ("")

# No required parameter: discovery needs none. Probing with no SCSIid fails on purpose and lists every LUN
# the backend can see; the root element name and SR_BACKEND_FAILURE_<n> code both vary between XenServer
# versions, so parse by tag name wherever BlockDevice occurs. sr-create formats the chosen LUN -
# destructive.
create_hba_sr() {
    local sr_name h xml block scsi_id path sr
    sr_name=$(param sr_name "xe-example-hba")
    h=$(first_host)
    xml=$(probe_for_failure lvmohba host-uuid="$h")
    # sr-create formats the LUN: on shared FC storage name yours (scsi_id=); with none, the first is taken.
    local want rest
    want=$(param scsi_id "")
    rest=$xml
    while [[ $rest == *"<BlockDevice>"* ]]; do
        block=${rest#*<BlockDevice>}; rest=${block#*</BlockDevice>}; block="<BlockDevice>${block%%</BlockDevice>*}"
        scsi_id=$(xml_tag_text "$block" SCSIid)
        [ -z "$want" ] || [ "$scsi_id" = "$want" ] && break
        scsi_id=""
    done
    [ -n "$scsi_id" ] || { echo "no LUN with SCSIid $want is visible to this host" >&2; return 1; }
    path=$(xml_tag_text "$block" path)
    echo "Discovered LUN: SCSIid $scsi_id on $path"

    # SCSIid is all lvmohba needs - it is what XenCenter's New SR wizard sends. (The probe's <path> is
    # for display: on a real host it reads like "/dev/sde [sdc] [sdg] [sdi]", one entry per path.)
    sr=$(xe sr-create host-uuid="$h" type=lvmohba name-label="$sr_name" shared=true \
        device-config:SCSIid="$scsi_id")
    echo "Created HBA SR: $sr ($(( $(xe sr-param-get uuid=$sr param-name=physical-size) / 1024 / 1024 / 1024 )) GiB)"
    detach_and_forget_sr $sr
    echo "OK: create-hba-sr"
}
