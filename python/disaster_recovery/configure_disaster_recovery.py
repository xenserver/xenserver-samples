"""Configure disaster recovery.

Turn on pool metadata replication: the pool writes its database - the configuration of its VMs and
vApps - to a disk on an iSCSI or Fibre Channel SR. Have your storage array replicate that SR, and the
VMs' SRs, to the disaster recovery site; a pool there can then recover the VMs from the replica (see
disaster_recovery_failover).

Run it::

    configure_disaster_recovery("https://xenserver", "root", password)
"""

import XenAPI

from connection import connect


def configure_disaster_recovery(url, username, password, sr_name=None):
    """Replicate the pool's metadata to an SR that can hold it (sr_name, or the first that can).

    Only SRs on a LUN - iSCSI or Fibre Channel/SAS (HBA) - can hold the pool's database, and every
    host must have the SR attached. The server says which qualify: SR.assert_supports_database_replication
    fails for any that can't (an NFS SR fails SR_OPERATION_NOT_SUPPORTED), so ask each one rather than
    guessing from its type, as the Configure DR dialog does. A pool can replicate to up to 8 SRs.

    Replication is only useful while it is on. So that the example leaves the pool as it found it, it
    turns replication off again if it was off to start with; in practice, leave it on."""
    session = connect(url, username, password)
    x = session.xenapi

    def supports_replication(sr):
        try:
            x.SR.assert_supports_database_replication(sr)
            return True
        except XenAPI.Failure:
            return False

    candidates = [sr for sr, r in x.SR.get_all_records().items()
                  if r["shared"] and r["content_type"] != "iso" and supports_replication(sr)]
    print("SRs that can hold the pool metadata: %s"
          % (", ".join(x.SR.get_name_label(sr) for sr in candidates) or "none"))
    if sr_name:
        candidates = [sr for sr in candidates if x.SR.get_name_label(sr) == sr_name]
    if not candidates:
        raise RuntimeError("no SR here can hold the pool metadata%s: it needs an iSCSI or Fibre Channel "
                           "SR attached to every host" % (" named %r" % sr_name if sr_name else ""))
    sr = candidates[0]
    name = x.SR.get_name_label(sr)

    # The pool's own metadata disk on this SR is what says replication is on (as the Configure DR
    # dialog decides): a disk of type "metadata" whose metadata_of_pool is this pool.
    pool = x.pool.get_all()[0]

    def metadata_disk():
        return next((v for v in x.SR.get_VDIs(sr)
                     if x.VDI.get_type(v) == "metadata" and x.VDI.get_metadata_of_pool(v) == pool), None)

    was_on = metadata_disk() is not None
    if was_on:
        print("The pool metadata is already replicated to %s" % name)
    else:
        print("Replicating the pool metadata to %s" % name)
        x.SR.enable_database_replication(sr)

    vdi = metadata_disk()
    print("  metadata disk: %s (%s), %d MiB, up to date: %s"
          % (x.VDI.get_name_label(vdi), x.VDI.get_uuid(vdi), int(x.VDI.get_virtual_size(vdi)) // (1024 * 1024),
             x.VDI.get_metadata_latest(vdi)))

    if not was_on:
        # Turning replication off destroys the metadata disk.
        x.SR.disable_database_replication(sr)
        print("Turned replication off again, as it was before")
    print("OK: configure-disaster-recovery")
    session.logout()
