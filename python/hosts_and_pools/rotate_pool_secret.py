"""Rotate the pool secret.

Rotate the shared secret that authenticates pool members to each other.
"""

import XenAPI

from connection import connect


def rotate_pool_secret(url, username, password):
    """Rotate the shared secret pool members authenticate to each other with.

    xapi checks its own preconditions before rotating - HA must be disabled, every host must be
    live, no rolling pool upgrade may be in progress, and the pool must be licensed for it - and
    raises a clear error naming which one failed rather than silently refusing. Report that
    explanation instead of letting an unhandled XenAPI.Failure speak for itself."""
    session = connect(url, username, password)
    pool_ref = list(session.xenapi.pool.get_all_records().keys())[0]
    print("Pool:           %s" % session.xenapi.pool.get_name_label(pool_ref))

    explanations = {
        "HA_IS_ENABLED": "HA is enabled on this pool; disable it first.",
        "CANNOT_CONTACT_HOST": "a host in the pool is not reachable.",
        "NOT_SUPPORTED_DURING_UPGRADE": "a rolling pool upgrade is in progress.",
        "LICENCE_RESTRICTION": "this edition is not licensed for pool secret rotation.",
    }
    try:
        # A pool-wide operation; existing sessions survive it.
        session.xenapi.pool.rotate_secret()
        print("Rotated. Still connected: %s" % (len(session.xenapi.pool.get_all()) == 1))
    except XenAPI.Failure as e:
        print("Could not rotate the pool secret: %s (%s)"
              % (e.details[0], explanations.get(e.details[0], "see the error for detail")))
    print("OK: rotate-pool-secret")
    session.xenapi.session.logout()
