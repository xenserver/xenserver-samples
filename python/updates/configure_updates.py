"""Configure updates (CDN).

Point the pool at a CDN update repository and turn on automatic update sync: register a repository,
set it as the pool's repository, enable update sync, read it back, then tidy up.

Run it::

    configure_updates("https://xenserver", "root", password, "https://repo.ops.xenserver.com/xs9",
    "https://repo-src.ops.xenserver.com/xs9")
"""

from connection import connect
from helpers import introduce_update_repositories


def configure_updates(url, username, password, repo_url, source_url):
    """Point the pool at the CDN's repositories and enable automatic update sync."""
    session = connect(url, username, password)
    repos = introduce_update_repositories(session, repo_url, source_url)
    print("Introduced repositories: %s"
          % ", ".join(session.xenapi.Repository.get_name_label(r) for r in repos))

    pool = session.xenapi.pool.get_all()[0]
    # Remember the pool's own repositories, to put them back afterwards.
    previous = session.xenapi.pool.get_repositories(pool)
    session.xenapi.pool.set_repositories(pool, repos)
    session.xenapi.pool.set_update_sync_enabled(pool, True)
    print("Pool repositories: %d; auto-sync enabled: %s"
          % (len(session.xenapi.pool.get_repositories(pool)),
             session.xenapi.pool.get_update_sync_enabled(pool)))

    # Tidy up so the example is repeatable.
    session.xenapi.pool.set_update_sync_enabled(pool, False)
    session.xenapi.pool.set_repositories(pool, previous)
    for repo in repos:
        session.xenapi.Repository.forget(repo)
    print("OK: configure-updates")
    session.xenapi.session.logout()
