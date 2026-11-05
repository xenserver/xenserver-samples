"""Change the root password.

Change the local superuser password, then change it back.

Run it::

    change_root_password("https://xenserver", "root", password)
"""

import secrets

from connection import connect


def change_root_password(url, username, password):
    """Change the local superuser password, then change it back."""
    session = connect(url, username, password)
    temporary = secrets.token_urlsafe(18)

    # change_password takes the OLD password as well as the new one, even though you are already
    # authenticated.
    session.xenapi.session.change_password(password, temporary)
    print("Password changed.")
    try:
        # The existing session stays valid afterwards - only NEW connections need the new password.
        print("Session still usable: %s" % (len(session.xenapi.pool.get_all()) == 1))

        # change_password on a ROOT session ignores the old password entirely (CA-13567): the call
        # succeeds whatever old_pwd is, so there is no wrong-old-password failure to demonstrate here.
        # The real gate is who may call this at all: only a local superuser session.
        print("Is local superuser (may call change_password): %s"
              % session.xenapi.session.get_is_local_superuser(session._session))
    finally:
        # Put the original password back however the above went, so a failure part-way through
        # doesn't leave root on the temporary one.
        session.xenapi.session.change_password(temporary, password)
    print("Password restored.")
    print("OK: change-root-password")
    session.xenapi.session.logout()
