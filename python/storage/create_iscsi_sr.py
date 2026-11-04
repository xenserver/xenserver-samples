"""Create an iSCSI SR.

Connect a storage repository to a LUN on an iSCSI target, discovering the target's IQNs and then the
LUNs behind one, as the New SR wizard does. Creating the SR formats the LUN, and a shared array
offers many targets, so name yours with target_iqn.
"""

import xml.etree.ElementTree as ET

from connection import connect
from helpers import detach_and_forget_sr, probe_for_failure


def create_iscsi_sr(url, username, password, target, port=None, chap_user=None, chap_password=None,
                     target_iqn=None, sr_name="sdk-example-iscsi"):
    """Connect an SR to a LUN on the iSCSI target, discovering the IQN and the LUN the way the New
    SR wizard does: a device-config that's missing a piece makes the backend fail on purpose, and
    the failure carries an XML fragment listing what it needs next.

    SR.create formats the chosen LUN - this is destructive, so pick carefully on a real target:
    pass target_iqn to name yours (see _choose_target_iqn)."""
    GIB = 1024 * 1024 * 1024
    session = connect(url, username, password)
    host = session.xenapi.host.get_all()[0]
    dc = {"target": target}
    if port:
        dc["port"] = str(port)
    if chap_user:
        dc["chapuser"] = chap_user
        dc["chappassword"] = chap_password

    # First failing probe: target only -> the backend lists the IQNs it offers.
    iqn_xml = ET.fromstring(probe_for_failure(session, host, dc, "lvmoiscsi"))
    dc["targetIQN"] = _choose_target_iqn(iqn_xml, target, target_iqn)
    print("Discovered IQN: %s" % dc["targetIQN"])

    # Second failing probe: +targetIQN -> the backend lists the LUNs behind it. Real create also
    # carries LUNid whenever it is known.
    lun_xml = ET.fromstring(probe_for_failure(session, host, dc, "lvmoiscsi"))
    luns = lun_xml.findall(".//LUN")
    lun = luns[0]
    dc["SCSIid"] = lun.find("SCSIid").text
    lun_id = lun.find("LUNid")
    dc["LUNid"] = lun_id.text if lun_id is not None else str(luns.index(lun))
    print("Discovered LUN %s (SCSIid %s)" % (dc["LUNid"], dc["SCSIid"]))

    sr = session.xenapi.SR.create(host, dc, "0", sr_name,
                                  "iSCSI SR created by the SDK example", "lvmoiscsi", "user", True, {})
    print("Created SR: %s (%d GiB)"
          % (session.xenapi.SR.get_uuid(sr), int(session.xenapi.SR.get_physical_size(sr)) // GIB))
    detach_and_forget_sr(session, sr)
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
