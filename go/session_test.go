package testGoSDK

import (
	"testing"

	xenapi "github.com/xenserver/xenserver-samples/go/goSDK"
)

func TestHTTPSConnection(t *testing.T) {
	if *CA_CERT_PATH_FLAG == "" {
		t.Log("CA certificate is not provided, skipping https connection test")
		t.Fail()
		return
	}
	// Test HTTPS connection without certificate verification
	session1 := xenapi.NewSession(&xenapi.ClientOpts{
		URL: "https://" + *IP_FLAG,
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
			URL: "https://" + *IP_FLAG,
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
