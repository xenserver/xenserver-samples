package testGoSDK

import (
	"strings"
	"testing"

	"xenapi"
)

func GetURL(ip string, tls bool) string {
	scheme := "http://"
	if tls {
		scheme = "https://"
	}
	if !strings.HasPrefix(ip, "http://") && !strings.HasPrefix(ip, "https://") {
		return scheme + ip
	}
	return ip
}

func TestHTTPConnection(t *testing.T) {
	session1 := xenapi.NewSession(&xenapi.ClientOpts{
		URL: GetURL(*IP_FLAG, false),
	})

	_, err := session1.LoginWithPassword(*USERNAME_FLAG, *PASSWORD_FLAG, "1.0", "Go sdk samples")
	if err != nil {
		t.Log(err)
		t.Fail()
		return
	}

	err = session1.Logout()
	if err != nil {
		t.Log(err)
		t.Fail()
		return
	}
}

func TestHTTPSConnection(t *testing.T) {
	if *CA_CERT_PATH_FLAG == "" {
		t.Skip("CA certificate is not provided, skipping https connection test")
	}
	// Test HTTPS connection without certificate verification
	session1 := xenapi.NewSession(&xenapi.ClientOpts{
		URL: GetURL(*IP_FLAG, true),
	})

	_, err := session1.LoginWithPassword(*USERNAME_FLAG, *PASSWORD_FLAG, "1.0", "Go sdk samples")
	if err != nil {
		t.Log(err)
		t.Fail()
		return
	}

	err = session1.Logout()
	if err != nil {
		t.Log(err)
		t.Fail()
		return
	}

	// Test HTTPS connection with server certificate verification
	if session.APIVersion >= xenapi.APIVersion2_21 {
		/* the CA cert in yangtze servers is missing fields, which will cause x509 error:
		   "cannot validate certificate for x.x.x.x because it doesn't contain any IP SANs"
		   skip this test case.
		*/
		session2 := xenapi.NewSession(&xenapi.ClientOpts{
			URL: GetURL(*IP_FLAG, true),
			SecureOpts: &xenapi.SecureOpts{
				ServerCert: *CA_CERT_PATH_FLAG,
			},
		})

		_, err = session2.LoginWithPassword(*USERNAME_FLAG, *PASSWORD_FLAG, "1.0", "Go sdk samples")
		if err != nil {
			t.Log(err)
			t.Fail()
			return
		}

		err = session2.Logout()
		if err != nil {
			t.Log(err)
			t.Fail()
			return
		}
	}
}
