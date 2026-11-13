"""Manage TLS certificates.

Install a pool-wide CA certificate, reset a host's server certificate, read the resulting
fingerprints back, and turn on verification of the certificates members present to each other.
"""

import os
import subprocess
import tempfile

from connection import connect


def manage_certificates(url, username, password):
    """Install a pool-wide trusted certificate, replace a host's own TLS identity with a real
    certificate, reset it back to a fresh self-signed one, and read the counts back.

    A real, generated self-signed certificate, not a placeholder string: xapi decodes whatever is
    handed to install_trusted_certificate/install_server_certificate as PEM and rejects anything
    that isn't a well-formed certificate (INVALID_VALUE), so a dummy string fails.
    install_trusted_certificate/uninstall_trusted_certificate are the current API; the
    CA-specific pair this example used to call (install_ca_certificate/uninstall_ca_certificate)
    were deprecated in their favour."""
    session = connect(url, username, password)
    host_ref = session.xenapi.host.get_all()[0]
    pool_ref = session.xenapi.pool.get_all()[0]
    cert_pem, key_pem = _self_signed_cert_pem()

    print("Certificates:   %d" % len(session.xenapi.Certificate.get_all()))

    # ca=True: trusted as a root to verify a chain, not pinned as one specific leaf certificate.
    # purpose=[]: general pool trust, not the licensing/ldaps-specific uses that enum also covers.
    # install_trusted_certificate returns nothing, so find the new record by diffing the set.
    before = set(session.xenapi.Certificate.get_all())
    session.xenapi.pool.install_trusted_certificate(pool_ref, True, cert_pem, [])
    cert_ref = next(iter(set(session.xenapi.Certificate.get_all()) - before))
    print("After CA add:   %d" % len(session.xenapi.Certificate.get_all()))

    # Actually replace the host's own TLS identity with a real certificate (what this workflow's
    # name promises, beyond CA trust), then reset it back to a fresh self-signed one.
    session.xenapi.host.install_server_certificate(host_ref, cert_pem, key_pem, "")
    print("Host certificate replaced with a real, generated certificate.")
    session.xenapi.host.reset_server_certificate(host_ref)
    print("Host certificate reset (a fresh self-signed identity).")

    session.xenapi.pool.uninstall_trusted_certificate(pool_ref, cert_ref)
    print("After CA remove:%d" % len(session.xenapi.Certificate.get_all()))

    # Separately from which certificates exist: whether the pool actually CHECKS the ones its members
    # present to each other. Turning it on is a one-way door from here -- there is no matching disable,
    # because a pool that could be talked out of verifying would not be verifying -- so the call is
    # idempotent and safe to repeat.
    pool = session.xenapi.pool.get_all()[0]
    print("TLS verification: %s" % session.xenapi.pool.get_tls_verification_enabled(pool))
    session.xenapi.pool.enable_tls_verification()
    print("  after enabling: %s" % session.xenapi.pool.get_tls_verification_enabled(pool))
    print("OK: manage-certificates")
    session.xenapi.session.logout()


def _self_signed_cert_pem():
    """A throwaway self-signed certificate and private key (PEM).

    Prefers the `cryptography` package (pure Python, no external tool needed) when it's installed;
    falls back to shelling out to `openssl req -x509` when it isn't, so this works either way
    without forcing an extra dependency on everyone."""
    try:
        import datetime
        from cryptography import x509
        from cryptography.hazmat.primitives import hashes, serialization
        from cryptography.hazmat.primitives.asymmetric import rsa
        from cryptography.x509.oid import NameOID

        key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
        name = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, "sdk-example")])
        now = datetime.datetime.utcnow()
        cert = (x509.CertificateBuilder()
                .subject_name(name).issuer_name(name).public_key(key.public_key())
                .serial_number(x509.random_serial_number())
                .not_valid_before(now - datetime.timedelta(days=1))
                .not_valid_after(now + datetime.timedelta(days=365))
                .sign(key, hashes.SHA256()))
        cert_pem = cert.public_bytes(serialization.Encoding.PEM).decode()
        key_pem = key.private_bytes(
            serialization.Encoding.PEM, serialization.PrivateFormat.TraditionalOpenSSL,
            serialization.NoEncryption()).decode()
        return cert_pem, key_pem
    except ImportError:
        handle, keypath = tempfile.mkstemp(prefix="sdk-example-key-", suffix=".pem")
        os.close(handle)
        handle, certpath = tempfile.mkstemp(prefix="sdk-example-cert-", suffix=".pem")
        os.close(handle)
        try:
            subprocess.run(
                ["openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes",
                 "-keyout", keypath, "-out", certpath, "-days", "365", "-subj", "/CN=sdk-example"],
                check=True, capture_output=True)
            with open(certpath) as f:
                cert_pem = f.read()
            with open(keypath) as f:
                key_pem = f.read()
            return cert_pem, key_pem
        finally:
            os.remove(keypath)
            os.remove(certpath)
