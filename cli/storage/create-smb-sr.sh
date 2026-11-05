# Create an SMB SR.
#
# Connect a shared storage repository to an SMB/CIFS file share, passing the server, share path and
# credentials (the password as a secret, never in plain text).
#
# Run it:
#   ./workflows.sh create-smb-sr https://xenserver root "$password"
#
# Optional key=value arguments (default):
#   server (192.0.2.40)
#   share (/vmstore)
#   smb_username (Administrator)
#   smb_password (Password1)
#   sr_name (xe-example-smb)

create_smb_sr() {
    local server share smb_username smb_password sr_name secret sr
    server=$(param server "192.0.2.40")
    share=$(param share "/vmstore")
    smb_username=$(param smb_username "Administrator")
    smb_password=$(param smb_password "Password1")
    sr_name=$(param sr_name "xe-example-smb")

    # The password travels as a Secret, not plaintext device-config (0/3 real captured sr-create calls for
    # this type use plaintext).
    secret=$(xe secret-create value="$smb_password")
    sr=$(xe sr-create host-uuid=$(first_host) type=smb name-label="$sr_name" shared=true \
        device-config:server="//$server$share" \
        device-config:username="$smb_username" device-config:password_secret=$secret)
    echo "Created SMB SR: $sr ($(( $(xe sr-param-get uuid=$sr param-name=physical-size) / 1024 / 1024 / 1024 )) GiB)"
    detach_and_forget_sr $sr
    xe secret-destroy uuid=$secret
    echo "OK: create-smb-sr"
}
