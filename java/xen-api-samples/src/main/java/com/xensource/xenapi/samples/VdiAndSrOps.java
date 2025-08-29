/*
 * Copyright (c) Cloud Software Group, Inc.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 *
 *   1) Redistributions of source code must retain the above copyright
 *      notice, this list of conditions and the following disclaimer.
 *
 *   2) Redistributions in binary form must reproduce the above
 *      copyright notice, this list of conditions and the following
 *      disclaimer in the documentation and/or other materials
 *      provided with the distribution.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
 * "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
 * LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS
 * FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE
 * COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT,
 * INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 * (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
 * SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT,
 * STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 * ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED
 * OF THE POSSIBILITY OF SUCH DAMAGE.
 */

package com.xensource.xenapi.samples;

import java.io.IOException;
import java.util.HashMap;
import java.util.UUID;
import java.util.Set;

import com.xensource.xenapi.*;

/**
 * Performs various SR and VDI tests, including creating a dummy SR.
 */
public class VdiAndSrOps extends TestBase {

    private static final String TEST_VDI_NAME = "TestVDI: DO NOT USE (created by VdiAndSrOps.java)";
    private static final long TEST_VDI_SIZE = 10L * 1024 * 1024;
    private static final String TEST_SR_NAME = "TestSR: DO NOT USE (created by VdiAndSrOps.java)";
    private static final String TEST_SR_DESC = "Should be automatically deleted";
    private static final String TEST_SR_TYPE = "dummy";
    private static final String TEST_SR_CONTENT = "contenttype";
    private static final long TEST_SR_SIZE = 100000L;

    public String getTestName() {
        return "VdiAndSrOps";
    }

    protected void TestCore() throws Exception {
        HashMap<String, String> emptyMap = new HashMap<>();

        HashMap<String, String> fullMap = new HashMap<>();
        fullMap.put("testKey", "testValue");

        final String[] srOps = {
                "SR.create",
                "SR.forget",
                "SR.createAsync",
                "SR.forget",
                "SR.introduce",
                "SR.forget",
                "SR.introduceAsync",
                "SR.forget"
        };

        for (String srOp : srOps) {
            log("--attempting " + srOp + " with null smConfig... ");
            srOpLong(connection, emptyMap, srOp);
            log("success");
        }

        for (String srOp : srOps) {
            log("--attempting " + srOp + " with non-null smConfig... ");
            srOpLong(connection, fullMap, srOp);
            log("success");
        }

        final String[] vdiOps = {
                "VDI.create",
                "VDI.snapshot",
                "VDI.createClone",
                "VDI.snapshotAsync",
                "VDI.createCloneAsync",
                "VDI.destroy"
        };

        for (String vdiOp : vdiOps) {
            log("--attempting " + vdiOp + " with null driverParams");
            vdiOpLong(connection, emptyMap, vdiOp);
            log("success");
        }

        for (String vdiOp : vdiOps) {
            log("--attempting " + vdiOp + " with non-null driverParams");
            vdiOpLong(connection, fullMap, vdiOp);
            log("success");
        }
    }

    private void vdiOpLong(Connection c, HashMap<String, String> driverParams, String op) throws Exception {
        try {
            VDI vdi;
            switch (op) {
                case "VDI.create":
                    var sr = findSrForVdi(c);
                    var vdiRec = newVdiRecord(sr);
                    VDI.create(c, vdiRec);
                    break;
                case "VDI.snapshot":
                    vdi = VDI.getByNameLabel(c, TEST_VDI_NAME).iterator().next();
                    vdi.snapshot(c, driverParams);
                    break;
                case "VDI.createClone":
                    vdi = VDI.getByNameLabel(c, TEST_VDI_NAME).iterator().next();
                    vdi.createClone(c, driverParams);
                    break;
                case "VDI.snapshotAsync":
                    vdi = VDI.getByNameLabel(c, TEST_VDI_NAME).iterator().next();
                    vdi.snapshotAsync(c, driverParams);
                    break;
                case "VDI.createCloneAsync":
                    vdi = VDI.getByNameLabel(c, TEST_VDI_NAME).iterator().next();
                    vdi.createCloneAsync(c, driverParams);
                    break;
                case "VDI.destroy":
                    var vdis = VDI.getByNameLabel(c, TEST_VDI_NAME);
                    for (var v : vdis) {
                        v.destroy(c);
                    }
                    break;
                default:
                    throw new Exception("Unknown API call.");
            }
        }
        catch (Types.HandleInvalid ex) {
            log("Expected error: HANDLE_INVALID.");
        }
    }

    private VDI.Record newVdiRecord(SR sr) {
        VDI.Record vdiRec = new VDI.Record();
        vdiRec.readOnly = false;
        vdiRec.SR = sr;
        vdiRec.virtualSize = TEST_VDI_SIZE;
        vdiRec.nameLabel = TEST_VDI_NAME;
        vdiRec.sharable = false;
        vdiRec.type = Types.VdiType.USER;
        vdiRec.smConfig = new HashMap<>() {{ put("vmhint", ""); }};
        return vdiRec;
    }

    private SR findSrForVdi(Connection c) throws IOException {
        var srs = SR.getAllRecords(c);
        var sms = SM.getAllRecords(c);

        for (var srPair : srs.entrySet()) {
            var srRec = srPair.getValue();

            if (srRec.contentType.equals("iso") || srRec.type.equals("tmpfs"))
                continue;

            for (var smRec : sms.values()) {
                if (smRec.type.equals(srRec.type) && smRec.features.containsKey("VDI_CREATE"))
                {
                    log("Found SR " + srRec.nameLabel);
                    return srPair.getKey();
                }
            }
        }
        return null;
    }

    private void srOpLong(Connection c, HashMap<String, String> smConfig, String op) throws Exception {
        try {
            Host our_host = (Host) Host.getAll(c).toArray()[0];

            switch (op) {
                case "SR.create":
                    SR.create(c, our_host, new HashMap<>(), TEST_SR_SIZE, TEST_SR_NAME, TEST_SR_DESC,
                            TEST_SR_TYPE, TEST_SR_CONTENT, true, smConfig);
                    break;
                case "SR.createAsync":
                    Task t1 = SR.createAsync(c, our_host, new HashMap<>(), TEST_SR_SIZE, TEST_SR_NAME, TEST_SR_DESC,
                            TEST_SR_TYPE, TEST_SR_CONTENT, true, smConfig);
                    waitForTask(c, t1, 500);
                    break;
                case "SR.forget":
                    Set<SR> srs = SR.getByNameLabel(c, TEST_SR_NAME);
                    for (SR sr : srs) {
                        // First destroy any PBDs associated with the SR
                        Set<PBD> pbds = PBD.getAll(c);
                        for (PBD pbd : pbds) {
                            if (pbd.getSR(c).equals(sr)) {
                                pbd.unplug(c);
                                try {
                                    pbd.destroy(c);
                                }
                                catch (Types.XenAPIException ex) {
                                    logger.log(ex.getMessage());
                                }
                            }
                        }
                        sr.forget(c);
                    }
                    break;
                case "SR.introduce":
                    SR.introduce(c, UUID.randomUUID().toString(), TEST_SR_NAME, TEST_SR_DESC, TEST_SR_TYPE, TEST_SR_CONTENT, true, smConfig);
                    break;
                case "SR.introduceAsync":
                    Task t2 = SR.introduceAsync(c, UUID.randomUUID().toString(), TEST_SR_NAME, TEST_SR_DESC, TEST_SR_TYPE, TEST_SR_CONTENT, true, smConfig);
                    waitForTask(c, t2, 500);
                    break;
                default:
                    throw new Exception("Unknown API call.");
            }
        }
        catch (Types.SrUnknownDriver ex) {
            log("SR unknown driver.");
        }
        catch (Types.XenAPIException ex) {
            if (ex.errorDescription != null && ex.errorDescription.length > 0) {
                if ("SR_BACKEND_FAILURE_102".equals(ex.errorDescription[0])) {
                    log("The request is missing the server parameter.");
                    return;
                }
                else if ("SR_BACKEND_FAILURE_101".equals(ex.errorDescription[0])) {
                    log("The request is missing the serverpath parameter.");
                    return;
                }
            }

            throw ex;
        }
    }
}
