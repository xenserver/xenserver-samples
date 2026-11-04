"""Clear a host's crash dumps.

Find the crash dumps a host kept after a failure, report how big and how old they are, then delete
them to free the space.
"""

from connection import connect


def manage_crash_dumps(url, username, password):
    """Find and delete the crash dumps a host kept after a failure.

    When a host crashes it writes a dump to its local disk and keeps it. They are large, they
    are never cleaned up on their own, and on a host that has crashed more than once they add
    up -- so clearing them once support has what it needs is ordinary housekeeping."""
    session = connect(url, username, password)
    x = session.xenapi

    # Crash dumps belong to the host that wrote them, so clear them a host at a time.
    host = next((h for h in x.host.get_all() if x.host.get_crashdumps(h)), None)
    if host is None:
        print("No crash dumps in this pool -- nothing to clear.")
        print("OK: manage-crash-dumps")
        session.logout()
        return

    dumps = x.host.get_crashdumps(host)
    total = 0
    print("%s has %d crash dump(s)" % (x.host.get_name_label(host), len(dumps)))
    for ref in dumps:
        record = x.host_crashdump.get_record(ref)
        total += int(record["size"])
        print("  %s  %s" % (record["timestamp"], mib(record["size"])))
    print("  %s in total" % mib(total))

    # Deleting a dump frees the space on the host; the host itself is untouched.
    for ref in dumps:
        x.host_crashdump.destroy(ref)
    print("  cleared:  %s now has %d"
          % (x.host.get_name_label(host), len(x.host.get_crashdumps(host))))

    print("OK: manage-crash-dumps")
    session.logout()


def mib(size):
    return "%d MiB" % (int(size) // (1024 * 1024))
