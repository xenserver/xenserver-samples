package main

import (
	"crypto/rand"
	"crypto/rsa"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/pem"
	"fmt"
	"math/big"
	"time"

	"go/xenapi"
)

// manageCertificates - Manage TLS certificates.
//
// Install a pool-wide CA certificate, reset a host's server certificate, read the resulting
// fingerprints back, and turn on verification of the certificates members present to each other.
func manageCertificates(url, user, password string) {
	session := connect(url, user, password)
	hosts, err := xenapi.Host.GetAll(session)
	check(err)
	pools, err := xenapi.Pool.GetAll(session)
	check(err)
	poolRef := pools[0]

	// A real, generated self-signed certificate, not a placeholder string: xapi decodes whatever is
	// handed to install_trusted_certificate/install_server_certificate as PEM and rejects anything
	// that isn't a well-formed certificate (INVALID_VALUE).
	certPEM, keyPEM := selfSignedCertPEM()

	certs, _ := xenapi.Certificate.GetAll(session)
	fmt.Printf("Certificates:   %d\n", len(certs))

	// ca=true: trusted as a root to verify a chain, not pinned as one specific leaf certificate.
	// purpose=[]: general pool trust. install_trusted_certificate is the current API (the
	// deprecated install_ca_certificate/uninstall_ca_certificate pair took a name instead) and
	// returns nothing, so find the new record by diffing the set.
	before := map[xenapi.CertificateRef]bool{}
	for _, ref := range certs {
		before[ref] = true
	}
	check(xenapi.Pool.InstallTrustedCertificate(session, poolRef, true, certPEM, []xenapi.CertificatePurpose{}))
	certs, _ = xenapi.Certificate.GetAll(session)
	fmt.Printf("After CA add:   %d\n", len(certs))
	var certRef xenapi.CertificateRef
	for _, ref := range certs {
		if !before[ref] {
			certRef = ref
			break
		}
	}

	// Actually replace the host's own TLS identity with a real certificate (beyond CA trust), then
	// reset it back to a fresh self-signed one, as before.
	check(xenapi.Host.InstallServerCertificate(session, hosts[0], certPEM, keyPEM, ""))
	fmt.Println("Host certificate replaced with a real, generated certificate.")
	check(xenapi.Host.ResetServerCertificate(session, hosts[0]))
	fmt.Println("Host certificate reset (a fresh self-signed identity).")

	check(xenapi.Pool.UninstallTrustedCertificate(session, poolRef, certRef))
	certs, _ = xenapi.Certificate.GetAll(session)
	fmt.Printf("After CA remove:%d\n", len(certs))

	// Separately from which certificates exist: whether the pool actually CHECKS the ones its members
	// present to each other. Turning it on is a one-way door from here - there is no matching disable,
	// because a pool that could be talked out of verifying would not be verifying - so the call is
	// idempotent and safe to repeat.
	verifying, _ := xenapi.Pool.GetTLSVerificationEnabled(session, poolRef)
	fmt.Printf("TLS verification: %t\n", verifying)
	check(xenapi.Pool.EnableTLSVerification(session))
	verifying, _ = xenapi.Pool.GetTLSVerificationEnabled(session, poolRef)
	fmt.Printf("  after enabling: %t\n", verifying)
	fmt.Println("OK: manage-certificates")
	session.Logout()
}

// selfSignedCertPEM generates a throwaway self-signed certificate and private key (PEM). Go's
// standard library crypto/x509 and crypto/rsa need no external tool for this, unlike some other
// languages here.
func selfSignedCertPEM() (certPEM, keyPEM string) {
	key, err := rsa.GenerateKey(rand.Reader, 2048)
	check(err)
	template := x509.Certificate{
		SerialNumber: big.NewInt(time.Now().UnixNano()),
		Subject:      pkix.Name{CommonName: "sdk-example"},
		NotBefore:    time.Now().Add(-24 * time.Hour),
		NotAfter:     time.Now().Add(365 * 24 * time.Hour),
	}
	der, err := x509.CreateCertificate(rand.Reader, &template, &template, &key.PublicKey, key)
	check(err)
	certPEM = string(pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: der}))
	keyPEM = string(pem.EncodeToMemory(&pem.Block{Type: "RSA PRIVATE KEY", Bytes: x509.MarshalPKCS1PrivateKey(key)}))
	return
}
