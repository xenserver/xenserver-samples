"""Configure updates for an air-gapped pool.

Switch a pool with no internet access to offline updates: make an update bundle repository the pool's
only repository, upload an update bundle (.xsbundle) to it if you have one, list the updates it makes
available, then tidy up.

Run it::

    configure_offline_updates("https://xenserver", "root", password, bundle_path="XS9-update.xsbundle")
"""

import json
import os
import ssl
import time
import urllib.request

from connection import connect


def configure_offline_updates(url, username, password, bundle_path=None):
    """Make a bundle repository the pool's only repository and upload bundle_path (an .xsbundle) to it.

    A pool that cannot reach the CDN takes its updates from a bundle you download elsewhere. The pool
    needs a repository of the bundle kind (it can have only one: Repository.introduce_bundle refuses a
    second with BUNDLE_REPOSITORY_ALREADY_EXISTS, so use the existing one), and it must be the pool's
    only enabled repository. Uploading is an HTTP PUT to /bundle alongside the API, with the session id and
    a task in the query string: the pool unpacks and checks the bundle, and the task says how that went.
    GET /updates then lists what the bundle offers each host, and host.apply_updates applies it with
    the hash in that list (see apply-update). Without bundle_path this only switches the channel and
    back."""
    session = connect(url, username, password)
    x = session.xenapi
    pool = x.pool.get_all()[0]
    ctx = ssl._create_unverified_context()

    # Remember the pool's own repositories, to put them back afterwards.
    previous = x.pool.get_repositories(pool)
    existing = [r for r, rec in x.Repository.get_all_records().items() if rec["origin"] == "bundle"]
    repo = existing[0] if existing else x.Repository.introduce_bundle("sdk-example-offline",
                                                                      "Updates from uploaded bundles")
    try:
        x.pool.set_repositories(pool, [repo])
        print("Pool repositories: %s" % ", ".join(x.Repository.get_name_label(r)
                                                  for r in x.pool.get_repositories(pool)))

        if bundle_path:
            task = x.task.create("sdk-example-bundle-upload", "")
            try:
                with open(bundle_path, "rb") as f:
                    request = urllib.request.Request(
                        "%s/bundle?session_id=%s&task_id=%s" % (url, session._session, task), data=f,
                        method="PUT", headers={"Content-Length": str(os.path.getsize(bundle_path))})
                    urllib.request.urlopen(request, context=ctx).read()
                while x.task.get_status(task) == "pending":
                    time.sleep(1)
                if x.task.get_status(task) != "success":
                    raise RuntimeError("bundle upload failed: %s" % x.task.get_error_info(task))
            finally:
                x.task.destroy(task)
            print("Uploaded %s" % os.path.basename(bundle_path))

            with urllib.request.urlopen("%s/updates?session_id=%s" % (url, session._session),
                                        context=ctx) as response:
                available = json.loads(response.read())
            print("Updates in the bundle: %d (apply them with hash %s)"
                  % (len(available.get("updates", [])), available.get("hash", "")))
        else:
            print("No bundle given: pass bundle_path to upload one")
    finally:
        # Forgetting a repository the pool still has enabled fails (REPOSITORY_IS_IN_USE): restore first.
        x.pool.set_repositories(pool, previous)
        if not existing:
            x.Repository.forget(repo)
    print("OK: configure-offline-updates")
    session.logout()
