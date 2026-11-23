# Read workload-balancing recommendations.
#
# Point the pool at a workload-balancing appliance, read its placement recommendations for the pool and for
# one VM, then disconnect it.
#
# Run it:
#   ./workflows.sh wlb-recommendations https://xenserver root "$password"
#
# Optional key=value arguments (default):
#   vm_name (web-01)
#   wlb_host_port (wlb.example:8012)
#   wlb_username (wlbuser)
#   wlb_password (wlbpass)
#   wlb_certificate ("")

# Needs a real, reachable WLB appliance: pool-initialize-wlb makes a synchronous HTTP call to it and fails
# if it can't connect - there is no way to fake this with a placeholder. wlb_host_port is host:port, with
# NO URL scheme - that is the real wire format (as a real pool sends it), not a URL; the old hard-coded
# value had an incorrect "https://" prefix. Also note: this command's own parameter names are an exception
# to xe's usual hyphenated convention - they are genuinely underscored on the wire.
#
# The pool checks the appliance's TLS certificate (wlb-verify-cert), and only against the certificates
# installed with pool-certificate-install - not pool-install-trusted-certificate's (a different store).
# A fresh appliance has a self-signed one, so pass it as wlb_certificate (a PEM file): without it
# pool-initialize-wlb fails with "Connection failed: configuration failed." and no hint that the
# certificate is the reason. pool-certificate-install is deprecated for pool-install-ca-certificate, but
# it is the same call either way (xapi_pool.ml aliases them) - and it names the certificate after the
# file's own basename rather than taking a name= parameter, so the file is copied to the name wanted
# for uninstalling it again.
wlb_recommendations() {
    local vm_name wlb_host_port wlb_username wlb_password wlb_certificate vm pool out deadline
    # Neither local: the EXIT trap below reads them after this function has returned.
    wlb_cert_name=""
    wlb_initialized=false
    vm_name=$(param vm_name "web-01")
    wlb_host_port=$(param wlb_host_port "wlb.example:8012")
    wlb_username=$(param wlb_username "wlbuser")
    wlb_password=$(param wlb_password "wlbpass")
    wlb_certificate=$(param wlb_certificate "")

    # Disconnect from the appliance - only if connecting it succeeded - and uninstall the certificate, if
    # one was installed, however the rest of this goes. Registered before either call so the cleanup is
    # conditional on what has actually been done by the time something fails. This script dispatches to
    # exactly one workflow and then exits, so an EXIT trap is bash's try/finally.
    trap '[ "$wlb_initialized" = true ] && remote_xe_try pool-deconfigure-wlb; [ -z "$wlb_cert_name" ] || remote_xe_try pool-certificate-uninstall name="$wlb_cert_name"' EXIT
    if [ -n "$wlb_certificate" ]; then
        wlb_cert_name=sdk-example-wlb.pem
        cp "$wlb_certificate" "$wlb_cert_name"
        remote_xe pool-certificate-install filename="$wlb_cert_name"
        rm -f "$wlb_cert_name"
    fi
    # The passwords here are pool-initialize-wlb's own parameters, which xe has no file form for.
    remote_xe pool-initialize-wlb wlb_url="$wlb_host_port" wlb_username="$wlb_username" \
        wlb_password="$wlb_password" xenserver_username="$user" xenserver_password="$pass"
    wlb_initialized=true

    # Initializing connects the pool to the appliance but leaves balancing off: every WLB call after this
    # would fail WLB_DISABLED until it's switched on.
    pool=$(remote_xe pool-list --minimal)
    remote_xe pool-param-set uuid=$pool wlb-enabled=true
    echo "WLB: $(remote_xe pool-list params=wlb-url --minimal)"

    # One line per recommendation, keyed by VM: "wlb", the destination host UUID, two ids, the reason.
    remote_xe pool-retrieve-wlb-recommendations

    # A VM's own recommendations are keyed by host and star-rate each as a destination - higher is better
    # (a real appliance rated hosts 6.1 here, so not capped at five). Right after connecting, the appliance
    # is still discovering the pool: WLB_INTERNAL_ERROR 4024 ("Pool discovery has not been started"), 4025
    # ("... has not been completed"), then 4016 ("WLB does not have current metrics") - keep asking for a
    # while. xe prints the error's message, not its code, so match on the text.
    vm=$(vm_uuid "$vm_name")
    deadline=$((SECONDS + 600))
    while true; do
        if out=$(remote_xe_try vm-retrieve-wlb-recommendations uuid=$vm 2>&1); then break; fi
        case "$out" in
            *4024*|*4025*|*"Pool discovery has not been"*|*4016*|*"does not have current metrics"*) ;;
            *) echo "$out" >&2; exit 1 ;;
        esac
        if [ $SECONDS -gt $deadline ]; then echo "$out" >&2; exit 1; fi
        sleep 15
    done
    printf '%s\n' "$out"

    # The appliance's own settings are read and written as one flat map of strings. Send a nightly
    # reporting schedule, then read the configuration back to confirm it took.
    remote_xe pool-send-wlb-configuration config:ReportingCronString="0 3 * * *"
    echo "  appliance configuration: $(remote_xe pool-retrieve-wlb-configuration)"

    ok wlb-recommendations
}
