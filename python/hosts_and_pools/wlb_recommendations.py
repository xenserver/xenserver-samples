"""Read workload-balancing recommendations.

Point the pool at a workload-balancing appliance, read its placement recommendations for the pool
and for one VM, then disconnect it.

Run it::

    wlb_recommendations("https://xenserver", "root", password, "web-01",
    wlb_host_port="192.0.2.60:30601", wlb_username="wlbuser", wlb_password="wlbpass",
    wlb_certificate="wlb-appliance.pem")
"""

import time

import XenAPI

from connection import connect


def wlb_recommendations(url, username, password, vm_name, wlb_host_port="wlb.example:8012",
                         wlb_username="wlbuser", wlb_password="wlbpass", wlb_certificate=""):
    """Connect a workload-balancing appliance and read its placement advice.

    Needs a real, reachable WLB appliance: pool.initialize_wlb makes a synchronous HTTP call to it
    and raises WLB_CONNECTION_REFUSED/WLB_CONNECTION_RESET if it can't connect - there is no way to
    fake this with a placeholder. wlb_host_port is host:port, with no URL scheme - that is the
    real wire format (xe pool-initialize-wlb wlb_url="10.x.x.x:30601" ...), not a URL.

    The pool checks the appliance's TLS certificate (pool.wlb_verify_cert), and only against the
    certificates installed with pool.certificate_install - not install_trusted_certificate's. A
    fresh appliance has a self-signed one, so pass it as wlb_certificate (a PEM file): without it
    initialize_wlb fails with INTERNAL_ERROR "Connection failed: configuration failed." and no
    hint that the certificate is the reason."""
    session = connect(url, username, password)
    x = session.xenapi
    pool = x.pool.get_all()[0]

    cert_name = ""
    if wlb_certificate:
        cert_name = "sdk-example-wlb.pem"
        with open(wlb_certificate) as f:
            x.pool.certificate_install(cert_name, f.read())   # a pool-wide call: no pool argument
    x.pool.initialize_wlb(wlb_host_port, wlb_username, wlb_password, username, password)
    try:
        # Initializing connects the pool to the appliance but leaves balancing off: every WLB call
        # after this would fail WLB_DISABLED until it's switched on.
        x.pool.set_wlb_enabled(pool, True)
        print(f"WLB: {x.pool.get_wlb_url(pool)}")

        # Read BY POSITION, and the two calls do not share a shape. The pool's recommendations are
        # keyed by VM and say where to move it: [0] "wlb", [1] the destination host's UUID (a uuid,
        # not a ref), [2] and [3] ids, [4] the reason. A freshly connected pool has none yet.
        for vm_ref, fields in x.pool.retrieve_wlb_recommendations().items():
            print(f"  move {x.VM.get_name_label(vm_ref)} -> host {fields[1]} ({fields[4]})")

        # A VM's own recommendations are keyed by host and star-rate each as a destination:
        # [0] "wlb", [1] the rating - higher is better (a real appliance rated hosts 6.1 here, so not capped
        # at five). Right after connecting, the appliance is still discovering the pool: WLB_INTERNAL_ERROR
        # 4024 ("Pool discovery has not been started"), 4025 ("... has not been completed"), then 4016 ("WLB
        # does not have current metrics") - keep asking.
        vm = x.VM.get_by_name_label(vm_name)[0]
        deadline = time.time() + 600
        while True:
            try:
                ratings = x.VM.retrieve_wlb_recommendations(vm)
                break
            except XenAPI.Failure as e:
                if (e.details[0] != "WLB_INTERNAL_ERROR" or e.details[1:2] not in (["4024"], ["4025"], ["4016"])
                        or time.time() > deadline):
                    raise
                time.sleep(15)
        for host, fields in ratings.items():
            print(f"  {x.host.get_name_label(host)} rated {fields[1]}")

        # The appliance's own settings are read and written as one flat map of strings. Send a
        # nightly reporting schedule, then read the configuration back to confirm it took.
        x.pool.send_wlb_configuration({"ReportingCronString": "0 3 * * *"})
        config = x.pool.retrieve_wlb_configuration()
        print("  appliance configuration: %s"
              % ", ".join("%s=%s" % kv for kv in sorted(config.items())))
    finally:
        # Disconnect from the appliance however the above went, or the pool stays attached to it.
        x.pool.deconfigure_wlb()
        if cert_name:
            x.pool.certificate_uninstall(cert_name)
    print("OK: wlb-recommendations")
    x.session.logout()
