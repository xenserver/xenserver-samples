# Manage TLS certificates.
#
# Install a pool-wide CA certificate, reset a host's server certificate, read the resulting fingerprints back,
# and turn on verification of the certificates members present to each other.
#
# Run it:
#   ./workflows.sh manage-certificates https://xenserver root "$password"

manage_certificates() {
    h=$(first_host)
    echo "Certificates:   $(count_csv "$(xe certificate-list --minimal)")"

    # A real, generated self-signed certificate, not a placeholder string: xapi decodes whatever is handed
    # to pool-install-trusted-certificate/host-server-certificate-install as PEM and rejects anything that
    # isn't a well-formed certificate (INVALID_VALUE). filename=/certificate=/private-key= are local files
    # xe uploads itself, the same convention vm-export/vm-import already use in this script.
    local certfile=cli-example-cert.pem keyfile=cli-example-key.pem before after cert_uuid
    rm -f "$certfile" "$keyfile"
    self_signed_cert "$certfile" "$keyfile"

    # pool-install-trusted-certificate/pool-uninstall-trusted-certificate are the current API; the
    # deprecated pool-*-ca-certificate pair (by name, not by uuid) is superseded by this one.
    # ca=true: trusted as a root to verify a chain, not pinned as one specific leaf certificate.
    before=$(xe certificate-list --minimal)
    xe pool-install-trusted-certificate filename="$certfile" ca=true
    after=$(xe certificate-list --minimal)
    echo "After CA add:   $(count_csv "$after")"
    cert_uuid=""
    for c in $(each_csv "$after"); do
        case ",$before," in *",$c,"*) ;; *) cert_uuid=$c ;; esac
    done

    # Actually replace the host's own TLS identity with a real certificate (what this workflow's name
    # promises, beyond CA trust), then reset it back to a fresh self-signed one.
    xe host-server-certificate-install uuid=$h certificate="$certfile" private-key="$keyfile"
    echo "Host certificate replaced with a real, generated certificate."
    xe host-reset-server-certificate uuid=$h
    echo "Host certificate reset (a fresh self-signed identity)."

    xe pool-uninstall-trusted-certificate certificate-uuid=$cert_uuid
    rm -f "$certfile" "$keyfile"
    echo "After CA remove:$(count_csv "$(xe certificate-list --minimal)")"

    # Separately from which certificates exist: whether the pool actually CHECKS the ones its members
    # present to each other. There is no matching disable - a pool that could be talked out of verifying
    # would not be verifying - and the enable is idempotent, so this is safe to repeat.
    p=$(first_csv "$(xe pool-list --minimal)")
    echo "TLS verification: $(xe pool-param-get uuid=$p param-name=tls-verification-enabled)"
    xe pool-enable-tls-verification
    echo "  after enabling: $(xe pool-param-get uuid=$p param-name=tls-verification-enabled)"
    echo "OK: manage-certificates"
}

# A throwaway self-signed certificate and private key (PEM). bash has no native crypto library, so
# shell out to openssl for this.
self_signed_cert() {
    local certfile=$1 keyfile=$2
    openssl req -x509 -newkey rsa:2048 -nodes -keyout "$keyfile" -out "$certfile" \
        -days 365 -subj /CN=sdk-example 2>/dev/null
}
