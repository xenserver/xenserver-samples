"""Trace API calls.

Send a W3C trace context with your API calls, so the work the pool does for them is recorded as part
of your application's distributed trace.

Run it::

    trace_api_calls("https://xenserver", "root", password)
"""

import os
import ssl
import xmlrpc.client

import XenAPI


def trace_api_calls(url, username, password):
    """Send a W3C trace context (a traceparent header) with every call, so the work the pool does for
    them is recorded as part of your application's distributed trace.

    XenAPI.Session sends the extra headers its transport is given. In an application instrumented with
    OpenTelemetry you would take the traceparent from the current span (opentelemetry.propagate.inject)
    rather than make one up as this does."""
    # version 00, a 16-byte trace id, the 8-byte id of the calling span, and flags 01 (sampled)
    trace_id = os.urandom(16).hex()
    traceparent = "00-%s-%s-01" % (trace_id, os.urandom(8).hex())

    def login(url):
        headers = [("traceparent", traceparent)]
        if url.startswith("https:"):
            # The host's certificate is self-signed: skip its validation, as connect() does.
            transport = xmlrpc.client.SafeTransport(context=ssl._create_unverified_context(), headers=headers)
        else:
            transport = xmlrpc.client.Transport(headers=headers)
        session = XenAPI.Session(url, transport=transport)
        session.login_with_password(username, password, "1.0", "sdk-examples")
        return session

    try:
        session = login(url)
    except XenAPI.Failure as e:
        if e.details[0] != "HOST_IS_SLAVE":
            raise
        session = login("https://%s" % e.details[1])  # the coordinator, as connect() does
    print("Trace %s: each call sends traceparent: %s" % (trace_id, traceparent))

    hosts = session.xenapi.host.get_all()
    print("The pool has %d hosts" % len(hosts))
    print("OK: trace-api-calls")
    session.xenapi.session.logout()
