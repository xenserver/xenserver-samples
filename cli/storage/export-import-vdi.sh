# Copy a disk's contents.
#
# Upload data into a virtual disk, download the disk's raw contents and copy them into a second disk, then
# check that the copy matches. Disk contents travel as HTTP transfers alongside the API.
#
# Run it:
#   ./workflows.sh export-import-vdi https://xenserver root "$password"
#
# Optional key=value arguments (default):
#   sr_name (Shared NFS)

# vdi-import and vdi-export move a disk's contents: xe does the HTTP transfer itself, against
# /import_raw_vdi or /export_raw_vdi, and waits for the server to finish with it. format=raw is every byte
# of the disk, so a raw export is as large as the disk's virtual size (format=vhd sends only the allocated
# blocks).
export_import_vdi() {
    local sr_name sr
    sr_name=$(param sr_name "Shared NFS")
    sr=$(remote_xe sr-list name-label="$sr_name" --minimal)
    sr=$(first_csv "$sr")
    # Not local: the EXIT trap below reads them after this function has returned.
    original=$(remote_xe vdi-create sr-uuid=$sr name-label=sdk-example-raw-source virtual-size=8MiB type=user)
    copy=$(remote_xe vdi-create sr-uuid=$sr name-label=sdk-example-raw-copy virtual-size=8MiB type=user)

    # Relative to the working directory: xe.exe and this script must agree on the path, and a Windows
    # temp directory spelled with backslashes would not survive the trip through both.
    data=cli-raw-source.bin exported=cli-raw-exported.bin
    trap 'remote_xe_try vdi-destroy uuid=$original; remote_xe_try vdi-destroy uuid=$copy; rm -f "$data" "$exported"' EXIT
    head -c $((8 * 1024 * 1024)) /dev/urandom > "$data"

    remote_xe vdi-import uuid=$original filename="$data" format=raw
    echo "Uploaded 8 MiB into sdk-example-raw-source"

    # xe refuses to write over an existing file, so clear one left by an earlier, interrupted run.
    rm -f "$exported"
    remote_xe vdi-export uuid=$original filename="$exported" format=raw
    echo "Downloaded $(( $(wc -c < "$exported") / 1024 / 1024 )) MiB of raw contents"

    remote_xe vdi-import uuid=$copy filename="$exported" format=raw
    echo "Copied them into sdk-example-raw-copy"

    rm -f "$exported"
    remote_xe vdi-export uuid=$copy filename="$exported" format=raw
    if cmp -s "$data" "$exported"; then
        echo "The copy matches the original"
    else
        echo "The copy DIFFERS FROM the original" >&2
        exit 1
    fi

    ok export-import-vdi
}
