"""Update an air-gapped pool from a bundle.

Update a pool that has no internet access from an update bundle (.xsbundle) downloaded elsewhere: make
a bundle repository the pool's update repository, upload the bundle, list the updates it offers, then
apply them host by host - coordinator first, moving each host's VMs to the rest of the pool - so the
VMs keep running throughout.

Run it::

    offline_pool_update("https://xenserver", "root", password, bundle_path="XS9-update.xsbundle")
"""

import json
import os
import ssl
import time
import urllib.request

from connection import connect
from helpers import (check_ha_and_wlb_off, check_hosts_can_be_evacuated, check_no_pending_guidance,
                     hosts_coordinator_first, report_vm_guidance, update_hosts)


def offline_pool_update(url, username, password, bundle_path):
    """Update every host in the pool from the update bundle at bundle_path.

    Check first, before changing anything, that the update can go through: HA and Workload Balancing
    off, no host or VM with mandatory guidance still pending from an earlier update, and every host
    able to empty. Then make a repository of the bundle kind the pool's only enabled repository - a
    pool can have only one (Repository.introduce_bundle refuses a second with
    BUNDLE_REPOSITORY_ALREADY_EXISTS), so use the existing one if there is one.

    Uploading is an HTTP PUT to /bundle alongside the API, with the session id and a task in the query
    string. The server answers 200 before it has read the bundle, so the task says how it went: the pool
    unpacks the bundle, checks its signature and syncs its updates before the task completes. GET
    /updates then lists what the bundle offers and the hash to apply it with, and
    helpers.update_hosts applies it to each host in turn as rolling-pool-update does. Finally report
    the guidance left for VMs, such as restarting one to pick the update up - that is the VM owner's
    call.

    A pool that stays air-gapped keeps its bundle repository for the next bundle; this example puts
    the pool's previous repositories back afterwards so that it can run again on a test pool."""
    session = connect(url, username, password)
    x = session.xenapi
    pool = x.pool.get_all()[0]
    ctx = ssl._create_unverified_context()
    hosts = hosts_coordinator_first(session)
    check_ha_and_wlb_off(session, pool)
    check_no_pending_guidance(session)
    check_hosts_can_be_evacuated(session, hosts)

    previous = x.pool.get_repositories(pool)
    existing = [r for r, rec in x.Repository.get_all_records().items() if rec["origin"] == "bundle"]
    repo = existing[0] if existing else x.Repository.introduce_bundle("sdk-example-offline",
                                                                      "Updates from uploaded bundles")
    try:
        x.pool.set_repositories(pool, [repo])
        print("Pool repositories: %s" % ", ".join(x.Repository.get_name_label(r)
                                                  for r in x.pool.get_repositories(pool)))

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
        updates = available.get("updates", [])
        print("Updates in the bundle: %d" % len(updates))
        for update in updates:
            print("  %s: %s" % (update.get("id", ""), update.get("summary", "")))
        if updates:
            session = update_hosts(session, url, username, password, hosts, available["hash"])
    finally:
        # Forgetting a repository the pool still has enabled fails (REPOSITORY_IS_IN_USE): restore first.
        session.xenapi.pool.set_repositories(pool, previous)
        if not existing:
            session.xenapi.Repository.forget(repo)
    report_vm_guidance(session)
    print("OK: offline-pool-update")
    session.xenapi.session.logout()
