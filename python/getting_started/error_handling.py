"""Handle an API error.

Catch an API failure and inspect its error code and parameters — the shape of every error the API
returns, and how to react to it robustly.

Run it::

    error_handling("https://xenserver", "root", password)
"""

import XenAPI

from connection import connect


def error_handling(url, username, password):
    """XenAPI errors surface as a XenAPI.Failure whose details are [CODE, param1, param2, ...]."""
    session = connect(url, username, password)
    try:
        session.xenapi.host.get_by_uuid("this-uuid-does-not-exist")
        print("unexpected: no error")
    except XenAPI.Failure as f:
        print("Caught expected failure: %s" % f.details[0])
        print("Short message: %s" % f)
    print("OK: error-handling")
    session.xenapi.session.logout()
