package testGoSDK

import (
	"flag"
	"os"
	"testing"

	"xenapi"
)

var IP_FLAG = flag.String("ip", "", "the URL of the form https://ip[:port] pointing at the server")
var USERNAME_FLAG = flag.String("username", "", "the username of the host (e.g. root)")
var PASSWORD_FLAG = flag.String("password", "", "the password of the host")
var CA_CERT_PATH_FLAG = flag.String("ca_cert_path", "", "the CA certificate file path for the host")
var NFS_SERVER_FLAG = flag.String("nfs_server", "", "the ip address pointing at the nfs server")
var NFS_PATH_FLAG = flag.String("nfs_path", "", "the nfs server path")
var IP1_FLAG = flag.String("ip1", "", "the URL of the form https://ip[:port] pointing at another host1")
var USERNAME1_FLAG = flag.String("username1", "", "the username of the host1 (e.g. root)")
var PASSWORD1_FLAG = flag.String("password1", "", "the password of the host1")

var session *xenapi.Session

func TestLogin(t *testing.T) {
	session = xenapi.NewSession(&xenapi.ClientOpts{
		URL: "http://" + *IP_FLAG,
		Headers: map[string]string{
			"User-Agent": "XS SDK for Go - Examples v1.0",
		},
	})
	_, err := session.LoginWithPassword(*USERNAME_FLAG, *PASSWORD_FLAG, "1.0", "Go sdk samples")
	if err != nil {
		t.Log(err)
		t.Fail()
		return
	}
	t.Log("api version: ", session.APIVersion)
	t.Log("xapi rpm version: ", session.XAPIVersion)
}

func TestMain(m *testing.M) {
	flag.Parse()
	exitVal := m.Run()
	var t *testing.T
	err := session.Logout()
	if err != nil {
		t.Log(err)
	}
	os.Exit(exitVal)
}
