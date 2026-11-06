"""Configure pool options.

Read and change the pool-wide options that govern how it behaves — live patching, IGMP snooping and
memory-migration compression — then put them back.

Run it::

    configure_pool_options("https://xenserver", "root", password)
"""

from connection import connect


def configure_pool_options(url, username, password):
    """Read and change the pool-wide options that govern how the pool behaves.

    These are plain pool settings, each a single field. Read them, change them, put them back."""
    session = connect(url, username, password)
    x = session.xenapi
    pool = x.pool.get_all()[0]

    before = {
        "live patching disabled": x.pool.get_live_patching_disabled(pool),
        "IGMP snooping":          x.pool.get_igmp_snooping_enabled(pool),
        "migration compression":  x.pool.get_migration_compression(pool),
    }
    for name, value in before.items():
        print("  %-22s %s" % (name, value))

    # Live patching applies host updates without a reboot; disabling it forces the reboot.
    x.pool.set_live_patching_disabled(pool, not before["live patching disabled"])
    # IGMP snooping keeps multicast off ports that did not ask for it.
    x.pool.set_igmp_snooping_enabled(pool, not before["IGMP snooping"])
    # Compression trades CPU for bandwidth when a VM's memory is moved between hosts.
    x.pool.set_migration_compression(pool, not before["migration compression"])

    print("after changing:")
    print("  %-22s %s" % ("live patching disabled", x.pool.get_live_patching_disabled(pool)))
    print("  %-22s %s" % ("IGMP snooping", x.pool.get_igmp_snooping_enabled(pool)))
    print("  %-22s %s" % ("migration compression", x.pool.get_migration_compression(pool)))

    x.pool.set_live_patching_disabled(pool, before["live patching disabled"])
    x.pool.set_igmp_snooping_enabled(pool, before["IGMP snooping"])
    x.pool.set_migration_compression(pool, before["migration compression"])
    print("  restored")
    print("OK: configure-pool-options")
    session.logout()
