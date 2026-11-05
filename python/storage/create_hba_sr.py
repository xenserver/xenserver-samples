"""Create an HBA SR.

Connect a shared storage repository to a fibre-channel (HBA) LUN: discover the LUNs the host can see
with a deliberately failing probe, then create the SR by SCSI ID. Creating the SR formats the LUN.
"""

import xml.etree.ElementTree as ET

from connection import connect
from helpers import probe_for_failure


def create_hba_sr(url, username, password, scsi_id="", sr_name="sdk-example-hba"):
    """Connect a shared SR to a fibre-channel (HBA) LUN, discovering it the way the New SR wizard
    does: probing with no SCSIid fails on purpose and lists every LUN the backend can see.

    SR.create formats the chosen LUN - this is destructive. On shared FC storage a host sees LUNs
    other hosts are using, so name the one that is yours (scsi_id); with none, the first LUN listed
    is taken, which is only right on a dedicated test target."""
    GIB = 1024 * 1024 * 1024
    session = connect(url, username, password)
    host = session.xenapi.host.get_all()[0]

    # The root element varies by backend; find BlockDevice entries by tag wherever they are.
    devlist_xml = ET.fromstring(probe_for_failure(session, host, {}, "lvmohba"))
    device = next((d for d in devlist_xml.iter("BlockDevice")
                   if not scsi_id or d.find("SCSIid").text == scsi_id), None)
    if device is None:
        raise RuntimeError("no LUN with SCSIid %s is visible to this host" % scsi_id)
    scsi_id = device.find("SCSIid").text
    path = device.find("path").text
    print("Discovered LUN: SCSIid %s on %s" % (scsi_id, path))

    # SCSIid is all lvmohba needs. (The probe's <path> is for display: on a real host it reads
    # like "/dev/sde [sdc] [sdg] [sdi]", one entry per path.)
    dc = {"SCSIid": scsi_id}

    # SCSIid alone is also enough to probe the LUN itself: an <SR> in the answer means one is already
    # there, and SR.create would format it. Reattach that SR rather than destroying it.
    srlist_xml = ET.fromstring(session.xenapi.SR.probe(host, dc, "lvmohba", {}))
    existing = srlist_xml.find("SR")
    if existing is not None:
        raise RuntimeError("LUN %s already holds SR %s; creating an SR here would format it - "
                            "reattach the existing SR instead of creating a new one"
                            % (scsi_id, existing.find("UUID").text.strip()))

    sr = session.xenapi.SR.create(host, dc, "0", sr_name,
                                  "HBA SR created by the SDK example", "lvmohba", "user", True, {})
    print("Created SR: %s (%d GiB)"
          % (session.xenapi.SR.get_uuid(sr), int(session.xenapi.SR.get_physical_size(sr)) // GIB))
    # Tidy up: this example created the SR, so destroy it - a forgotten SR would stay on the LUN.
    # SR.destroy needs it detached from every host first.
    for pbd in session.xenapi.SR.get_PBDs(sr):
        if session.xenapi.PBD.get_currently_attached(pbd):
            session.xenapi.PBD.unplug(pbd)
    session.xenapi.SR.destroy(sr)
    print("OK: create-hba-sr")
    session.logout()
