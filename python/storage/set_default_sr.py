"""Set the pool's default storage.

Choose where the pool puts new disks, suspended VMs' memory images and host crash dumps by default,
then put the original choice back.
"""

from connection import connect


def set_default_sr(url, username, password, nfs_server="192.0.2.10", nfs_path="/export/spare"):
    """Choose where the pool puts new disks, suspended VMs and crash dumps by default.

    These are three separate settings, not one. New disks land on the default SR, a
    suspended VM's memory image goes to the suspend-image SR and host crash dumps to the
    crash-dump SR -- they are usually the same storage, but they need not be."""
    session = connect(url, username, password)
    x = session.xenapi
    pool = x.pool.get_all()[0]

    # Capture all three separately. They are genuinely independent, and a pool that has
    # never suspended or crashed anything can legitimately leave the latter two unset -- so
    # restoring all three from the default would quietly invent settings that were not there.
    before = x.pool.get_default_SR(pool)
    before_suspend = x.pool.get_suspend_image_SR(pool)
    before_crash = x.pool.get_crash_dump_SR(pool)
    print("default storage:  %s" % sr_label(x, before))
    print("  suspend images: %s" % sr_label(x, before_suspend))
    print("  crash dumps:    %s" % sr_label(x, before_crash))

    # Somewhere to switch to. A pool default has to be reachable from every host, so it is
    # a shared SR; a local one would strand any VM whose disk landed on the wrong host.
    sr = x.SR.create(host_first(x), {"server": nfs_server, "serverpath": nfs_path, "nfsversion": "3"},
                     "0", "sdk-example-default", "SR used by the SDK default-storage example",
                     "nfs", "user", True, {})
    x.pool.set_default_SR(pool, sr)
    x.pool.set_suspend_image_SR(pool, sr)
    x.pool.set_crash_dump_SR(pool, sr)
    print("  switched to:    %s" % sr_label(x, x.pool.get_default_SR(pool)))

    # Restore the original choice before tidying up: an SR that is still the pool default is
    # the awkward one to remove.
    x.pool.set_default_SR(pool, before)
    x.pool.set_suspend_image_SR(pool, before_suspend)
    x.pool.set_crash_dump_SR(pool, before_crash)
    for pbd in x.SR.get_PBDs(sr):
        x.PBD.unplug(pbd)
    x.SR.forget(sr)
    print("  restored to:    %s" % sr_label(x, x.pool.get_default_SR(pool)))
    print("OK: set-default-sr")
    session.logout()


def host_first(x):
    return x.host.get_all()[0]


def sr_label(x, sr):
    """An SR's name, tolerating the null reference an unset pool field holds."""
    return x.SR.get_name_label(sr) if sr and sr != "OpaqueRef:NULL" else "(none)"
