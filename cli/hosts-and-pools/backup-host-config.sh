# Back up a host's configuration.
#
# Download a host's configuration backup and verify it downloaded. With restore=true, stage it back onto
# the same host's backup partition: host-restore does not restore the host there and then, it only writes
# the archive over that host's (currently inactive) backup partition, ready for the next boot.
#
# Run it:
#   ./workflows.sh backup-host-config https://xenserver root "$password"
#
# Optional key=value arguments (default):
#   restore (false)

backup_host_config() {
    local restore
    restore=$(param restore false)
    # Deliberately not `host`: that is the variable the xe() helper dials, and shadowing it here sent
    # every later command to a server named after the host's UUID.
    # The coordinator: always reachable at the pool's address. (Back up every host, in practice.)
    target=$(xe pool-param-get uuid=$(xe pool-list --minimal) param-name=master)
    echo "Backing up $(xe host-param-get uuid=$target param-name=name-label)"

    # Relative to the working directory: xe.exe and this script must agree on the path, and a Windows
    # temp directory spelled with backslashes would not survive the trip through both.
    file="cli-host.backup"
    rm -f "$file"   # xe refuses to overwrite an existing file rather than clobbering it
    # xe does the HTTP transfer itself: the server answers the command by telling the client to GET
    # /host_backup, and xe writes the file. Nothing streams down the CLI connection.
    xe host-backup uuid=$target file-name="$file"
    size=$(stat -c %s "$file" 2>/dev/null || wc -c < "$file")
    [ "$size" -gt 0 ] || { echo "backup-host-config: $file came back empty" >&2; exit 1; }
    echo "  wrote $size bytes to $file"

    if [ "$restore" = true ]; then
        # host-restore writes the archive over the host's own backup partition - the inactive one, never
        # the partition it is currently running from. It only takes effect once you boot that host from
        # the installer and choose Restore there.
        xe host-restore uuid=$target file-name="$file"
        echo "  staged it on $(xe host-param-get uuid=$target param-name=name-label)'s backup partition" \
             "- it takes effect only after booting that host from the installer and choosing Restore"
    else
        echo "  not restoring it (pass restore=true to stage it on $(xe host-param-get uuid=$target param-name=name-label)'s backup partition)"
    fi

    rm -f "$file"
    ok backup-host-config
}
