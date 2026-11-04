module github.com/xenserver/xenserver-samples/go/workflows

go 1.27.1

require go/xenapi v0.0.0

// The SDK's Go binding is not published as a module: copy XenServerGo/src from the SDK into ./goSDK.
// See README.md.
replace go/xenapi => ./goSDK
