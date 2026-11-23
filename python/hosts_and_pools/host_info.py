"""Host information.

Read a host's software version, edition and CPU topology (sockets and cores).

Run it::

    host_info("https://xenserver", "root", password)
"""

from connection import connect


def host_info(url, username, password):
    """Read a host's identity: product version, edition and CPU topology."""
    session = connect(url, username, password)
    host = next(iter(session.xenapi.host.get_all_records().values()))
    sw = host["software_version"]
    cpu = host["cpu_info"]
    print("Host:     %s" % host["name_label"])
    print("Version:  %s" % sw.get("product_version", "?"))
    print("Edition:  %s" % host["edition"])
    print("CPUs:     %s across %s socket(s)"
          % (cpu.get("cpu_count", "?"), cpu.get("socket_count", "?")))

    # The physical identity, straight off the host's DMI/SMBIOS tables. The serial number is what you
    # quote to the hardware vendor, so it is the one field here that identifies this machine and not
    # just its model.
    bios = host["bios_strings"]
    print("Hardware: %s %s" % (bios.get("system-manufacturer", "?"),
                               bios.get("system-product-name", "?")))
    print("Serial:   %s" % bios.get("system-serial-number", "?"))
    print("BIOS:     %s" % bios.get("bios-version", "?"))
    print("OK: host-info")
    session.xenapi.session.logout()
