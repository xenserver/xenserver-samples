"""Create an iSCSI SR.

Connect a storage repository to a LUN on an iSCSI target, discovering the target's IQNs and then the
LUNs behind one, as the New SR wizard does. Creating the SR formats the LUN, and a shared array
offers many targets, so name yours with target_iqn; if the target behind it offers more than one
LUN, name yours with scsi_id too.
"""

import xml.etree.ElementTree as ET

from connection import connect
from helpers import probe_for_failure


def create_iscsi_sr(url, username, password, target, port=None, chap_user=None, chap_password=None,
                     target_iqn=None, scsi_id=None, sr_name="sdk-example-iscsi"):
    """Connect an SR to a LUN on the iSCSI target, discovering the IQN and the LUN the way the New
    SR wizard does: a device-config that's missing a piece makes the backend fail on purpose, and
    the failure carries an XML fragment listing what it needs next.

    SR.create formats the chosen LUN - this is destructive, so pick carefully on a real target:
    pass target_iqn to name yours (see _choose_target_iqn), and scsi_id too if more than one LUN
    is offered behind it (see _choose_lun). Before creating, this probes the chosen LUN itself to
    make sure it is not already in use by another SR - formatting over one would destroy it.

    The CHAP password (if any) travels as a Secret, not plaintext device-config, as create-smb-sr
    already does for its share password."""
    GIB = 1024 * 1024 * 1024
    session = connect(url, username, password)
    host = session.xenapi.host.get_all()[0]
    dc = {"target": target}
    if port:
        dc["port"] = str(port)
    secret = None
    if chap_user:
        dc["chapuser"] = chap_user
        secret = session.xenapi.secret.create({"value": chap_password, "other_config": {}})
        dc["chappassword_secret"] = session.xenapi.secret.get_uuid(secret)

    try:
        # First failing probe: target only -> the backend lists the IQNs it offers.
        iqn_xml = ET.fromstring(probe_for_failure(session, host, dc, "lvmoiscsi"))
        dc["targetIQN"] = _choose_target_iqn(iqn_xml, target, target_iqn)
        print("Discovered IQN: %s" % dc["targetIQN"])

        # Second failing probe: +targetIQN -> the backend lists the LUNs behind it. Real create also
        # carries LUNid whenever it is known.
        lun_xml = ET.fromstring(probe_for_failure(session, host, dc, "lvmoiscsi"))
        luns = lun_xml.findall(".//LUN")
        lun = _choose_lun(luns, scsi_id)
        dc["SCSIid"] = lun.find("SCSIid").text
        lun_id = lun.find("LUNid")
        dc["LUNid"] = lun_id.text if lun_id is not None else str(luns.index(lun))
        print("Discovered LUN %s (SCSIid %s)" % (dc["LUNid"], dc["SCSIid"]))

        # The device-config is now complete enough to create from - which means it is also complete
        # enough to probe the LUN itself: an <SR> in the answer means one is already there, and
        # SR.create would format it. Reattach that SR rather than destroying it.
        srlist_xml = ET.fromstring(session.xenapi.SR.probe(host, dc, "lvmoiscsi", {}))
        existing = srlist_xml.find("SR")
        if existing is not None:
            raise RuntimeError("LUN %s already holds SR %s; creating an SR here would format it - "
                                "reattach the existing SR instead of creating a new one"
                                % (dc["SCSIid"], existing.find("UUID").text.strip()))

        sr = session.xenapi.SR.create(host, dc, "0", sr_name,
                                      "iSCSI SR created by the SDK example", "lvmoiscsi", "user", True, {})
        print("Created SR: %s (%d GiB)"
              % (session.xenapi.SR.get_uuid(sr), int(session.xenapi.SR.get_physical_size(sr)) // GIB))
        # Tidy up: this example created the SR, so destroy it - a forgotten SR would stay on the LUN.
        # SR.destroy needs it detached from every host first.
        for pbd in session.xenapi.SR.get_PBDs(sr):
            if session.xenapi.PBD.get_currently_attached(pbd):
                session.xenapi.PBD.unplug(pbd)
        session.xenapi.SR.destroy(sr)
    finally:
        if secret:
            session.xenapi.secret.destroy(secret)
    print("OK: create-iscsi-sr")
    session.logout()


def _choose_target_iqn(iqn_xml, target, target_iqn):
    """Pick the IQN from an iSCSI discovery probe: the caller's, if named (it must be one the target
    offers), else the first. An array usually offers many targets - one per LUN, often belonging to
    different users - so on shared storage always name yours: SR.create formats the LUN behind it."""
    offered = [e.text for e in iqn_xml.findall(".//TargetIQN")]
    if target_iqn and target_iqn not in offered:
        raise RuntimeError("target %s does not offer IQN %s" % (target, target_iqn))
    return target_iqn or offered[0]


def _choose_lun(luns, scsi_id):
    """Pick the LUN behind the chosen IQN: the caller's SCSIid, if named (it must be one on offer),
    else the one LUN, if that target offers only one. The New SR wizard auto-selects a LUN only when
    exactly one is on offer, and otherwise makes the caller choose - picking blindly on a shared
    target risks formatting someone else's disk."""
    if scsi_id:
        for lun in luns:
            if lun.find("SCSIid").text == scsi_id:
                return lun
        raise RuntimeError("target does not offer a LUN with SCSIid %s; offered: %s"
                            % (scsi_id, ", ".join(lun.find("SCSIid").text for lun in luns)))
    if len(luns) == 1:
        return luns[0]
    offered = ", ".join("%s (%s bytes)" % (lun.find("SCSIid").text, lun.find("size").text) for lun in luns)
    raise RuntimeError("target offers %d LUNs; name one with scsi_id: %s" % (len(luns), offered))
