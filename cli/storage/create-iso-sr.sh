# Create an ISO library SR.
#
# Connect an ISO-library storage repository to a file share of ISO images (here an NFS export), so the images
# are available as installation media.
#
# Run it:
#   ./workflows.sh create-iso-sr https://xenserver root "$password"
#
# Optional key=value arguments (default):
#   location (192.0.2.10:/isos)

create_iso_sr() {
    # Connect an ISO-library SR to a file share of ISO images (here an NFS export, location
    # "server:/path").
    local location
    location=$(param location "192.0.2.10:/isos")
    sr=$(xe sr-create host-uuid=$(first_host) type=iso name-label=xe-example-iso content-type=iso \
        device-config:location="$location" device-config:type=nfs_iso shared=true)
    echo "Created ISO SR: $sr"

    # A scan picks up the ISOs on the share as VDIs, which is what makes them selectable as
    # installation media.
    xe sr-scan uuid=$sr
    echo "ISO images: $(count_csv "$(xe vdi-list sr-uuid=$sr --minimal)")"

    detach_and_forget_sr $sr
    echo "Detached and forgot the SR."
    ok create-iso-sr
}
