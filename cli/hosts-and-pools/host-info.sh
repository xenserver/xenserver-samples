# Host information.
#
# Read a host's software version, edition and CPU topology (sockets and cores).
#
# Run it:
#   ./workflows.sh host-info https://xenserver root "$password"

host_info() {
    h=$(first_host)
    echo "Host:    $(xe host-param-get uuid=$h param-name=name-label)"
    echo "Version: $(xe host-param-get uuid=$h param-name=software-version param-key=product_version)"
    echo "Edition: $(xe host-param-get uuid=$h param-name=edition)"
    # The physical identity, straight off the host's DMI/SMBIOS tables. The serial number is what you
    # quote to the hardware vendor, so it identifies this machine and not just its model.
    echo "Hardware: $(xe host-param-get uuid=$h param-name=bios-strings param-key=system-manufacturer) $(xe host-param-get uuid=$h param-name=bios-strings param-key=system-product-name)"
    echo "Serial:   $(xe host-param-get uuid=$h param-name=bios-strings param-key=system-serial-number)"
    echo "BIOS:     $(xe host-param-get uuid=$h param-name=bios-strings param-key=bios-version)"
    echo "OK: host-info"
}
