"""Recover VMs after a disaster.

Replicate the pool's database to shared storage, read it back as a separate database to see what it
describes, and recover a VM out of it into a second, standby pool (dr_url).

Run it::

    disaster_recovery("https://xenserver", "root", password, dr_url="https://standby-pool")
"""

import XenAPI

from connection import connect


def disaster_recovery(url, username, password, dr_url=None):
    """Replicate the pool's database to shared storage, then recover a VM out of it onto a second,
    standby pool.

    Disaster recovery works by writing the pool's own database out to a storage repository
    as a disk of type "metadata". That disk can be read back as a SEPARATE database --
    VDI.open_database hands you a session scoped to it -- so the ordinary calls describe
    the pool as it was replicated rather than the pool you are connected to. Recovering
    reads from that database and writes into a live pool, which is why the recover call
    is made on the metadata session and takes a live session as its destination.

    That destination has to be a DIFFERENT, standby pool: recovering a VM back into the exact
    pool it was replicated from can't actually succeed with force=False. The VM's uuid already
    exists there, so VM.recover always takes the replace-or-fail path, and nothing replicated a
    moment ago from a live database can ever be "newer" than the live object it came from - it
    fails with VM_TO_IMPORT_IS_NOT_NEWER_VERSION. The one-line "fix" of passing force=True instead
    would make it succeed by REPLACING (destroying and recreating) the live original - exactly the
    opposite of what a DR demo should show. A second pool is the only way force=False succeeds (a
    brand-new VM object, not a replace), and it's what every real DR workflow actually does.
    Track the recovered VM by uuid, never by name: a name can coincidentally collide with
    something already on the destination pool, and tidy-up must never guess by name."""
    if not dr_url:
        raise RuntimeError("disaster-recovery needs a second pool to recover into: pass "
                            "dr_url=<url of a standby pool>")
    session = connect(url, username, password)
    dr_session = connect(dr_url, username, password)
    x = session.xenapi

    # Replication needs shared storage the standby pool can attach too, and only block storage (iSCSI,
    # HBA) supports it - an NFS SR fails SR_OPERATION_NOT_SUPPORTED. The server checks rather than taking
    # your word for it, so ask each candidate, as XenCenter's DR wizard does.
    def supports_replication(sr):
        try:
            x.SR.assert_supports_database_replication(sr)
            return True
        except XenAPI.Failure:
            return False
    sr = next((ref for ref, r in x.SR.get_all_records().items()
               if r["shared"] and r["content_type"] != "iso" and supports_replication(ref)), None)
    if sr is None:
        raise RuntimeError("no shared SR here supports database replication (it needs iSCSI or HBA storage)")
    print("Replicating pool metadata to %s" % x.SR.get_name_label(sr))
    x.SR.enable_database_replication(sr)

    # Everything from here happens on the STANDBY pool, the way XenCenter's DR wizard works from the
    # pool you fail over to: it has the same SR attached, rescans it to see the metadata disk just
    # written, opens the database there, and recovers into itself - VM.recover's session_to has to be a
    # session of the server running the call (HANDLE_INVALID otherwise).
    d = dr_session.xenapi
    try:
        dr_sr = d.SR.get_by_uuid(x.SR.get_uuid(sr))
    except XenAPI.Failure:
        raise RuntimeError("the standby pool has not attached %s: attach the same storage there first"
                           % x.SR.get_name_label(sr))
    d.SR.scan(dr_sr)
    vdi = next((v for v in d.SR.get_VDIs(dr_sr) if d.VDI.get_type(v) == "metadata"), None)
    if vdi is None:
        raise RuntimeError("the standby pool sees no metadata disk on %s after rescanning it"
                           % d.SR.get_name_label(dr_sr))
    print("  metadata disk: %s" % d.VDI.get_uuid(vdi))

    # A session onto the replicated database rather than the live pool. The binding keeps the
    # session id in _session, so a second Session can be pointed at the one we were handed.
    metadata = XenAPI.Session(dr_url, ignore_ssl=True)
    metadata._session = d.VDI.open_database(vdi)

    # Only real guest VMs are recoverable - exclude templates, control domains and snapshots.
    recoverable = {ref: r for ref, r in metadata.xenapi.VM.get_all_records().items()
                   if not r["is_a_template"] and not r["is_control_domain"] and not r["is_a_snapshot"]}
    print("  the replicated database describes %d recoverable VM(s)" % len(recoverable))

    # Only a VM whose disks are all on storage the standby pool can see can be recovered there - the
    # check runs on the METADATA session, and session_to says where the VM should land: the standby
    # pool's own session. Take the first (by name) that passes, as the DR wizard lists them.
    dr_session_id = dr_session._session
    def can_be_recovered(ref):
        try:
            metadata.xenapi.VM.assert_can_be_recovered(ref, dr_session_id)
            return True
        except XenAPI.Failure:
            return False
    target = next((ref for ref in sorted(recoverable, key=lambda ref: recoverable[ref]["name_label"])
                   if can_be_recovered(ref)), None)
    if target is None:
        raise RuntimeError("no VM in the replicated database has all its disks on storage the standby "
                           "pool can see")
    target_uuid = recoverable[target]["uuid"]
    name = recoverable[target]["name_label"]
    print("  recovering %s" % name)
    metadata.xenapi.VM.recover(target, dr_session_id, False)

    # It is a real VM on the standby pool now, not merely a call that returned - look it up by the
    # uuid full_restore preserved, not by name.
    recovered = dr_session.xenapi.VM.get_by_uuid(target_uuid)
    print("  %s is %s on the standby pool" % (name, dr_session.xenapi.VM.get_power_state(recovered)))

    # Tidy up on the standby pool only, by uuid - never touch the source pool's VMs, and never
    # guess by name (a coincidentally-same-named VM must not be destroyed). Destroy the VM record but
    # NOT its disks: they are the protected pool's own disks on the shared SR, not copies.
    dr_session.xenapi.VM.destroy(recovered)
    x.SR.disable_database_replication(sr)
    print("OK: disaster-recovery")
    session.xenapi.session.logout()
    dr_session.xenapi.session.logout()
