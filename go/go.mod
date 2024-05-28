module github.com/xenserver/xenserver-samples/go

go 1.22.2

replace xenapi => ./goSDK

require (
	github.com/google/uuid v1.6.0
	xenapi v0.0.0-00010101000000-000000000000
)
