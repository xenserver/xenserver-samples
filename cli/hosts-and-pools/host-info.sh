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
    # bios-strings is a VM field, not a host one - xe has no DMI/SMBIOS identity for a host, only its CPU
    # topology (cpu_info is a host field, with an underscore - the one exception to xe's usual convention).
    cpu_count=$(xe host-param-get uuid=$h param-name=cpu_info param-key=cpu_count)
    socket_count=$(xe host-param-get uuid=$h param-name=cpu_info param-key=socket_count)
    echo "CPUs:    $cpu_count across $socket_count socket(s)"
    ok host-info
}
