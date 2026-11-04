# Export and import a VM.
#
# Export a VM to an XVA file and import it back as a new one. These are HTTP transfers alongside the API
# rather than API calls, so the session id travels in the query string.
#
# Run it:
#   ./workflows.sh export-import-vm https://xenserver root "$password"
#
# Optional key=value arguments (default):
#   vm_name (db-01)

export_import_vm() {
    vm_name=$(param vm_name "db-01")
    # Name the VM: an export carries every block of its disks, so which VM matters (a large one takes a
    # long time, and fills the disk). Only a halted VM can be exported: its disks must not be changing
    # underneath the copy.
    vm=$(vm_uuid "$vm_name")
    [ "$(xe vm-param-get uuid=$vm param-name=power-state)" = "halted" ] ||
        { echo "$vm_name must be halted to be exported" >&2; exit 1; }
    echo "Exporting $vm_name"

    # Relative to the working directory: xe.exe and this script must agree on the path, and a Windows
    # temp directory spelled with backslashes would not survive the trip through both.
    file="cli-export.xva"
    # Always clean up the file, on failure too: a real export is gigabytes, not worth leaving behind.
    trap 'rm -f "$file"' EXIT
    # xe does the HTTP transfer itself: the server answers the command by telling the client to GET
    # /export, and xe writes the file. Nothing streams down the CLI connection.
    xe vm-export uuid=$vm filename="$file"
    size=$(stat -c %s "$file" 2>/dev/null || wc -c < "$file")
    # Check the file, not xe's exit status: Windows xe.exe reports a failed transfer ("Export failed")
    # and still exits 0.
    [ "${size:-0}" -gt 0 ] || { echo "the export produced no data" >&2; exit 1; }
    echo "  wrote $((size / 1024 / 1024)) MiB to $(basename "$file")"

    # The SDK languages have to create a task, pass its id as /import?task_id=, and poll it themselves to
    # recover the imported VM's ref - a real host's /import response body doesn't carry it. xe does all of
    # that internally and hands back the new VM's uuid directly, so there is nothing extra to do here.
    imported=$(xe vm-import filename="$file")
    echo "  imported as $(xe vm-param-get uuid=$imported param-name=name-label)"

    # The import brought its own disks along; vm-uninstall destroys those too, not just the VM record.
    xe vm-uninstall uuid=$imported force=true
    echo "OK: export-import-vm"
}
