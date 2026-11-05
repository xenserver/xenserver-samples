"""Small helpers several workflows share: finding objects by name, waiting for the guest agent,
tidying up what an example created."""

import time
import xml.etree.ElementTree as ET
import xmlrpc.client

import XenAPI

from connection import connect


def template_by_name(session, name):
    """Find a template VM by its exact name (rather than picking an arbitrary one)."""
    for ref, r in session.xenapi.VM.get_all_records().items():
        if r["is_a_template"] and r["name_label"] == name:
            return ref
    raise RuntimeError("no template named %r was found" % name)


def vm_by_name(session, name):
    """Find a guest VM (not a template, control domain or snapshot) by its exact name."""
    for ref, r in session.xenapi.VM.get_all_records().items():
        if (not r["is_a_template"] and not r["is_control_domain"]
                and not r["is_a_snapshot"] and r["name_label"] == name):
            return ref
    raise RuntimeError("no VM named %r was found" % name)


def sr_by_name(session, name, shared=False):
    """Find an SR by its exact name (optionally requiring it to be shared)."""
    for ref, r in session.xenapi.SR.get_all_records().items():
        if r["name_label"] == name and (not shared or r["shared"]):
            return ref
    raise RuntimeError("no %sSR named %r was found" % ("shared " if shared else "", name))


def detach_and_forget_sr(session, sr):
    """Detach an SR from every host, then forget it.

    SR.forget refuses an SR that is still attached (SR_HAS_PBD), so unplug its PBDs first. Forgetting
    drops the pool's record of the SR but leaves the data on the storage itself."""
    for pbd in session.xenapi.SR.get_PBDs(sr):
        if session.xenapi.PBD.get_currently_attached(pbd):
            session.xenapi.PBD.unplug(pbd)
    session.xenapi.SR.forget(sr)


def provision(session, vm):
    """Provision a cloned template into a real VM, filling in the SR first.

    A template's other_config["disks"] is <provision><disk ... sr="" .../></provision> - sr="" means
    "whoever provisions this names the SR". VM.provision takes it literally and fails with
    UUID_INVALID, so rewrite every <disk>'s sr to the pool's default SR first, exactly as
    `xe vm-install` does, before provisioning."""
    pool_ref = session.xenapi.pool.get_all()[0]
    sr_uuid = session.xenapi.SR.get_uuid(session.xenapi.pool.get_default_SR(pool_ref))

    disks_xml = session.xenapi.VM.get_other_config(vm).get("disks")
    if disks_xml:
        root = ET.fromstring(disks_xml)
        for disk in root.findall("disk"):
            disk.set("sr", sr_uuid)
        session.xenapi.VM.remove_from_other_config(vm, "disks")
        session.xenapi.VM.add_to_other_config(vm, "disks", ET.tostring(root, encoding="unicode"))

    session.xenapi.VM.provision(vm)


def copy_of_guest(session, source_vm_name, new_vm_name):
    """A throwaway VM with a working guest OS: a copy of an existing VM that has one.

    Suspend, checkpoint, live migration and clean shutdown all need the guest's cooperation: on a
    running VM with no PV drivers xapi refuses them up front with VM_LACKS_FEATURE (a VM freshly
    cloned from a template has no OS at all). So copy a VM that does have an OS and PV drivers,
    without disturbing it: snapshot it (fine while it runs), clone the snapshot - a clone of a
    snapshot is a template - and provision that into an ordinary VM. The snapshot is only needed
    for the clone, so it goes again straight away."""
    source = vm_by_name(session, source_vm_name)
    snapshot = session.xenapi.VM.snapshot(source, new_vm_name + "-source")
    vm = session.xenapi.VM.clone(snapshot, new_vm_name)
    provision(session, vm)
    destroy_vm_and_disks(session, snapshot)
    return vm


def wait_for_guest_agent(session, vm, timeout=300, interval=2):
    """Wait, after VM.start, until the guest's PV drivers have reported in.

    xapi only offers the guest-dependent operations once the guest says it can do them, and
    allowed_operations is where it says so: wait for clean_shutdown to appear there (the same
    check that refuses it with VM_LACKS_FEATURE beforehand). A Linux kernel offers that early in
    boot, before the agent runs (hot-plug needs the agent, and suspend needs its emulated disk
    unplugged), so wait for the guest metrics to report the PV drivers too. A booting OS takes a while."""
    def ready():
        if "clean_shutdown" not in session.xenapi.VM.get_allowed_operations(vm):
            return False
        metrics = session.xenapi.VM.get_guest_metrics(vm)
        return metrics != "OpaqueRef:NULL" and session.xenapi.VM_guest_metrics.get_PV_drivers_detected(metrics)

    deadline = time.time() + timeout
    while not ready():
        if time.time() > deadline:
            raise RuntimeError("the guest's PV drivers did not report in within %ds; does the source "
                               "VM have a guest OS with PV drivers (XenServer VM Tools)?" % timeout)
        time.sleep(interval)


def xml_from_failure(e):
    """The first (from the end) XenAPI.Failure detail that looks like an XML fragment, or None."""
    for detail in reversed(e.details):
        if detail and detail.lstrip().startswith("<"):
            return detail
    return None


def probe_for_failure(session, host, device_config, sm_type):
    """Return the XML a backend sends back on its deliberately-failing discovery probe.

    The New SR wizard discovers iSCSI/HBA LUNs by asking with an incomplete device-config on
    purpose: the backend can't create anything from it yet, so it fails with an
    SR_BACKEND_FAILURE_<n> error whose params carry an XML fragment describing what it found (the
    IQNs on offer, then the LUNs behind one of them, or - for HBA - every LUN visible at all). A
    probe that unexpectedly *succeeds* means the device-config was already complete - not the
    discovery prompt this helper is looking for. (Never probe by attempting SR.create instead: on
    real storage a create that succeeds formats the LUN.)"""
    try:
        session.xenapi.SR.probe(host, device_config, sm_type, {})
    except XenAPI.Failure as e:
        xml = xml_from_failure(e)
        if xml:
            return xml
        raise
    raise RuntimeError("SR.probe for %s succeeded without asking for more information; "
                       "check the target address" % sm_type)


def wait_for_restart(url, username, password, host_uuid, key, before, timeout=1800, interval=10):
    """Wait for a host to come back from a reboot (key "boot_time") or toolstack restart
    ("agent_start_time"): until that other_config entry differs from `before` and the host is live.
    Reconnects every time round, because the host restarting may be the coordinator this session
    talks to; returns the new session."""
    deadline = time.time() + timeout
    while True:
        try:
            session = connect(url, username, password)
            x = session.xenapi
            host = x.host.get_by_uuid(host_uuid)
            if x.host.get_other_config(host).get(key) != before and host_live(x, host):
                return session
            x.session.logout()
        except (OSError, xmlrpc.client.ProtocolError, XenAPI.Failure):
            pass                     # down, or xapi still starting
        if time.time() > deadline:
            raise RuntimeError("host %s did not come back in time" % host_uuid)
        time.sleep(interval)


def enable_when_booted(x, host, timeout=600, interval=10):
    """Re-enable a host that has just come back. It reports itself live before xapi on it has
    finished starting, and until then host.enable fails HOST_STILL_BOOTING - so retry that."""
    deadline = time.time() + timeout
    while True:
        try:
            x.host.enable(host)
            return
        except XenAPI.Failure as e:
            if e.details[0] != "HOST_STILL_BOOTING" or time.time() > deadline:
                raise
            time.sleep(interval)


def move_disks_to_sr(session, vm, sr_ref):
    """Relocate every one of a (not-yet-started) VM's disks onto the given SR, the same
    VDI.pool_migrate storage-migrate already demonstrates."""
    for vdi in disk_vdis(session, vm):
        if session.xenapi.VDI.get_SR(vdi) != sr_ref:
            session.xenapi.VDI.pool_migrate(vdi, sr_ref, {})


def disk_vdis(session, vm_ref):
    """The VDIs backing a VM's disk VBDs (used to clean up a full copy's independent disks)."""
    vdis = []
    for vbd in session.xenapi.VM.get_VBDs(vm_ref):
        if session.xenapi.VBD.get_type(vbd) != "Disk":
            continue
        vdi = session.xenapi.VBD.get_VDI(vbd)
        if vdi != "OpaqueRef:NULL":
            vdis.append(vdi)
    return vdis


def destroy_vm_and_disks(session, vm_ref):
    """Destroy a VM (or snapshot, or template) this example made, and the disks it owns.

    VM.destroy removes only the VM record, not its disks, so every workflow that created a VM
    (or a snapshot/checkpoint of one) and is tidying up after itself needs to destroy the backing
    VDIs too - exactly what delete-vm does by hand. A checkpoint (or a suspended VM) also owns a
    suspend image holding its memory, which no VBD points at: destroy that as well."""
    vdis = disk_vdis(session, vm_ref)
    suspend_vdi = session.xenapi.VM.get_suspend_VDI(vm_ref)
    if suspend_vdi != "OpaqueRef:NULL":
        vdis.append(suspend_vdi)
    session.xenapi.VM.destroy(vm_ref)
    for vdi in vdis:
        session.xenapi.VDI.destroy(vdi)


def introduce_update_repositories(session, repo_url, source_url):
    """Introduce the pool's update repositories: the release's base packages (update=False) and its
    update stream (update=True, which pool.sync_updates needs - otherwise NO_REPOSITORY_ENABLED). A
    real host checks the URLs (INVALID_BASE_URL for an unknown domain), so these are the XenServer
    CDN's, e.g. https://repo.ops.xenserver.com/xs9/{base,normal}."""
    return [session.xenapi.Repository.introduce(
                "sdk-example-%s" % stage, "SDK example %s repository" % stage,
                "%s/%s" % (repo_url, stage), "%s/%s" % (source_url, stage), stage != "base", "")
            for stage in ("base", "normal")]


def host_live(x, host):
    return x.host_metrics.get_live(x.host.get_metrics(host))
