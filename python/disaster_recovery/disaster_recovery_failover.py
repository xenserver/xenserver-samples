"""Fail over to the disaster recovery site.

On the pool at the disaster recovery site, attach the storage array's replica of the protected pool's
storage, read the pool metadata replicated to it, and recover the VMs and vApps it describes. By default
this is a test failover, which removes what it recovered and detaches the storage again.

Run it::

    disaster_recovery_failover("https://dr-site-pool", "root", password, target="192.0.2.31",
                               target_iqn="iqn.2009-01.com.example:replica-0", scsi_id="360a98...")
"""

import xml.etree.ElementTree as ET

import XenAPI

from connection import connect


def disaster_recovery_failover(url, username, password, target=None, target_iqn=None, scsi_id=None,
                               port=None, sr_type="lvmoiscsi", test_failover=True):
    """Recover the protected pool's VMs and vApps into this pool from the replica of its storage.

    The replica is the LUN the storage array mirrors the protected pool's SR to: name it by the iSCSI
    target, IQN and SCSI id (sr_type "lvmoiscsi"), or by SCSI id alone for Fibre Channel/SAS (sr_type
    "lvmohba"). Before a real failover, break the mirror so that this site can write to the replica, and
    make sure no other pool has those LUNs attached: two pools using the same LUN corrupt it.

    DR_task.create attaches every SR on the LUN that you name (by uuid) to this pool, keeping its uuid,
    and VDI.open_database gives a session onto the metadata replicated there - a separate, read-only
    database, not this pool. Recovering runs on that session and names this pool's session as the place
    to recover into. A test failover (test_failover=True) then removes the recovered VMs and vApps -
    not their disks, which are the replica's - and detaches and forgets the SRs."""
    if isinstance(test_failover, str):  # from the command line
        test_failover = test_failover.lower() != "false"
    session = connect(url, username, password)
    x = session.xenapi

    device_config = {"SCSIid": scsi_id}
    if sr_type == "lvmoiscsi":
        device_config.update({"target": target, "targetIQN": target_iqn})
        if port:
            device_config["port"] = str(port)

    # Which SRs are on the LUN, and which of them hold pool metadata. sm_config metadata=true asks for
    # their names and the pool_metadata_detected flag as well as their uuids.
    master = x.pool.get_master(x.pool.get_all()[0])
    found = ET.fromstring(x.SR.probe(master, device_config, sr_type, {"metadata": "true"}))
    srs = [(e.findtext("UUID").strip(), (e.findtext("name_label") or "").strip(),
            (e.findtext("pool_metadata_detected") or "").strip() == "true") for e in found.iter("SR")]
    for uuid, name, has_metadata in srs:
        print("Found SR %s (%s)%s" % (name, uuid, ", with pool metadata" if has_metadata else ""))
    if not srs:
        raise RuntimeError("there is no SR on that LUN")

    task = x.DR_task.create(sr_type, device_config, [uuid for uuid, _, _ in srs])
    introduced = x.DR_task.get_introduced_SRs(task)
    print("Attached %s" % ", ".join(x.SR.get_name_label(sr) for sr in introduced))

    # Recover from every replicated database on the attached SRs: vApps first (their VMs come with
    # them), then the VMs not in a vApp. A VM whose disks are on storage this pool hasn't attached
    # can't be recovered - assert_can_be_recovered says so (VM_REQUIRES_SR) - so skip it.
    recovered_vms, recovered_vapps = [], []
    for sr in introduced:
        for vdi in x.SR.get_VDIs(sr):
            if x.VDI.get_type(vdi) != "metadata" or not x.VDI.get_metadata_latest(vdi):
                continue
            database = XenAPI.Session(url, ignore_ssl=True)
            database._session = x.VDI.open_database(vdi)
            d = database.xenapi
            # A pool often has no name of its own; show its coordinator's name instead.
            pool = d.pool.get_all()[0]
            print("  pool metadata of %s" % (d.pool.get_name_label(pool)
                                             or d.host.get_name_label(d.pool.get_master(pool))))

            in_recovered_vapp = set()
            for vapp, record in d.VM_appliance.get_all_records().items():
                try:
                    d.VM_appliance.assert_can_be_recovered(vapp, session._session)
                except XenAPI.Failure as e:
                    print("  cannot recover vApp %s: %s" % (record["name_label"], e.details[0]))
                    continue
                d.VM_appliance.recover(vapp, session._session, False)
                recovered_vapps.append(record["uuid"])
                recovered_vms.extend(d.VM.get_uuid(vm) for vm in record["VMs"])
                in_recovered_vapp.update(record["VMs"])
                print("  recovered vApp %s" % record["name_label"])

            for vm, record in sorted(d.VM.get_all_records().items(), key=lambda kv: kv[1]["name_label"]):
                if (record["is_a_template"] or record["is_control_domain"] or record["is_a_snapshot"]
                        or vm in in_recovered_vapp):
                    continue
                try:
                    d.VM.assert_can_be_recovered(vm, session._session)
                except XenAPI.Failure as e:
                    print("  cannot recover %s: %s" % (record["name_label"], e.details[0]))
                    continue
                d.VM.recover(vm, session._session, False)
                recovered_vms.append(record["uuid"])
                print("  recovered %s" % record["name_label"])
            # Close the database. The binding's own logout is for sessions it logged in itself, so
            # make the call directly.
            database.session.logout(database._session)

    # The recovered VMs keep their uuids, so look them up by uuid - a name may be taken here already.
    for uuid in recovered_vms:
        vm = x.VM.get_by_uuid(uuid)
        print("%s is %s" % (x.VM.get_name_label(vm), x.VM.get_power_state(vm)))

    if test_failover:
        for uuid in recovered_vms:
            vm = x.VM.get_by_uuid(uuid)
            if x.VM.get_power_state(vm) != "Halted":
                x.VM.hard_shutdown(vm)
            x.VM.destroy(vm)
        for uuid in recovered_vapps:
            x.VM_appliance.destroy(x.VM_appliance.get_by_uuid(uuid))
    # Destroying the task detaches and forgets the SRs it attached that no recovered VM needs.
    x.DR_task.destroy(task)
    if test_failover:
        # The SRs the recovered VMs needed are no longer the task's: detach and forget those too.
        for sr in introduced:
            try:
                for pbd in x.SR.get_PBDs(sr):
                    if x.PBD.get_currently_attached(pbd):
                        x.PBD.unplug(pbd)
                x.SR.forget(sr)
            except XenAPI.Failure as e:
                if e.details[0] != "HANDLE_INVALID":  # already forgotten by DR_task.destroy
                    raise
        print("Test failover: removed the recovered VMs and detached the replica")
    else:
        print("Recovered VMs are halted: start them when you are ready")
    print("OK: disaster-recovery-failover")
    session.logout()
