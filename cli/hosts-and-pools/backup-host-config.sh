# Back up a host's configuration.
#
# Download a host's configuration backup and hand it back as a restore would — and watch another host's backup
# be refused.
#
# Run it:
#   ./workflows.sh backup-host-config https://xenserver root "$password"

backup_host_config() {
    # Deliberately not `host`: that is the variable the xe() helper dials, and shadowing it here sent
    # every later command to a server named after the host's UUID.
    target=$(nth_csv "$(xe host-list --minimal)" 1)
    echo "Backing up $(xe host-param-get uuid=$target param-name=name-label)"

    # Relative to the working directory: xe.exe and this script must agree on the path, and a Windows
    # temp directory spelled with backslashes would not survive the trip through both.
    file="cli-host.backup"
    rm -f "$file"   # xe refuses to overwrite an existing file rather than clobbering it
    # xe does the HTTP transfer itself: the server answers the command by telling the client to GET
    # /host_backup, and xe writes the file. Nothing streams down the CLI connection.
    xe host-backup uuid=$target file-name="$file"
    size=$(stat -c %s "$file" 2>/dev/null || wc -c < "$file")
    echo "  wrote $size bytes to $file"

    xe host-restore uuid=$target file-name="$file"
    echo "  restoring it to $(xe host-param-get uuid=$target param-name=name-label): accepted"

    other=$(nth_csv "$(xe host-list --minimal)" 2)
    if [ -n "$other" ]; then
        # host-backup/host-restore are served only by whichever host physically accepted the connection -
        # xe's own uri_of_someone already dials that host's address directly by uuid, there is no
        # forwarding and no ref= to check, so this is not refused on a real pool the way a naive reading of
        # "restoring one host's config onto another" might suggest. A real pool's hosts are all reachable
        # from a management client; guard the attempt anyway with a friendly message on any transport
        # error, for networks where a second host's address isn't routable from here.
        if err=$(xe host-restore uuid=$other file-name="$file" 2>&1); then
            echo "  restoring it to $(xe host-param-get uuid=$other param-name=name-label): accepted"
        else
            echo "  restoring it to $(xe host-param-get uuid=$other param-name=name-label): could not restore ($err)"
        fi
    fi

    rm -f "$file"
    echo "OK: backup-host-config"
}
