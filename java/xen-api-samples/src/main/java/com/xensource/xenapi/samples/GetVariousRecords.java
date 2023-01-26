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

import java.util.Map;

import com.xensource.xenapi.*;

/**
 * Retrieves and prints out records for various API objects.
 */
public class GetVariousRecords extends TestBase {
    public String getTestName() {
        return "GetVariousRecords";
    }

    protected void TestCore() throws Exception {
        log("We'll try to retrieve all the records for certain types of objects");
        log("This should exercise most of the marshalling code");

        testBondRecords();
        testHostRecords();
        testNetworkRecords();
        testPBDRecords();
        testPIFRecords();
        testPoolRecords();
        testSRRecords();
        testVBDRecords();
        testVDIRecords();
        testVIFRecords();
        testVMRecords();
    }

    private void testBondRecords() throws Exception {
        announce("Get all the Bond records");
        Map<Bond, Bond.Record> allrecords = Bond.getAllRecords(connection);
        log("Got: " + allrecords.size() + " records");
        if (allrecords.size() > 0) {
            log("Printing out the first Bond record:");
            log(allrecords.values().toArray()[0].toString());
        }
        log("");
    }

    private void testHostRecords() throws Exception {
        announce("Get all the Host records");
        Map<Host, Host.Record> allrecords = Host.getAllRecords(connection);
        log("Got: " + allrecords.size() + " records");
        if (allrecords.size() > 0) {
            log("Printing out the first Host record:");
            log(allrecords.values().toArray()[0].toString());
        }
        log("");
    }

    private void testNetworkRecords() throws Exception {
        announce("Get all the Network records");
        Map<Network, Network.Record> allrecords = Network.getAllRecords(connection);
        log("Got: " + allrecords.size() + " records");
        if (allrecords.size() > 0) {
            log("Printing out the first Network record:");
            log(allrecords.values().toArray()[0].toString());
        }
        log("");
    }

    private void testPBDRecords() throws Exception {
        announce("Get all the PBD records");
        Map<PBD, PBD.Record> allrecords = PBD.getAllRecords(connection);
        log("Got: " + allrecords.size() + " records");
        if (allrecords.size() > 0) {
            log("Printing out the first PBD record:");
            log(allrecords.values().toArray()[0].toString());
        }
        log("");
    }

    private void testPIFRecords() throws Exception {
        announce("Get all the PIF records");
        Map<PIF, PIF.Record> allrecords = PIF.getAllRecords(connection);
        log("Got: " + allrecords.size() + " records");
        if (allrecords.size() > 0) {
            log("Printing out the first PIF record:");
            log(allrecords.values().toArray()[0].toString());
        }
        log("");
    }

    private void testPoolRecords() throws Exception {
        announce("Get all the Pool records");
        Map<Pool, Pool.Record> allrecords = Pool.getAllRecords(connection);
        log("Got: " + allrecords.size() + " records");
        if (allrecords.size() > 0) {
            log("Printing out the first Pool record:");
            log(allrecords.values().toArray()[0].toString());
        }
        log("");
    }

    private void testSRRecords() throws Exception {
        announce("Get all the SR records");
        Map<SR, SR.Record> allrecords = SR.getAllRecords(connection);
        log("Got: " + allrecords.size() + " records");
        if (allrecords.size() > 0) {
            log("Printing out the first SR record:");
            log(allrecords.values().toArray()[0].toString());
        }
        log("");
    }

    private void testVBDRecords() throws Exception {
        announce("Get all the VBD records");
        Map<VBD, VBD.Record> allrecords = VBD.getAllRecords(connection);
        log("Got: " + allrecords.size() + " records");
        if (allrecords.size() > 0) {
            log("Printing out the first VBD record:");
            log(allrecords.values().toArray()[0].toString());
        }
        log("");
    }

    private void testVDIRecords() throws Exception {
        announce("Get all the VDI records");
        Map<VDI, VDI.Record> allrecords = VDI.getAllRecords(connection);
        log("Got: " + allrecords.size() + " records");
        if (allrecords.size() > 0) {
            log("Printing out the first VDI record:");
            log(allrecords.values().toArray()[0].toString());
        }
        log("");
    }

    private void testVIFRecords() throws Exception {
        announce("Get all the VIF records");
        Map<VIF, VIF.Record> allrecords = VIF.getAllRecords(connection);
        log("Got: " + allrecords.size() + " records");
        if (allrecords.size() > 0) {
            log("Printing out the first VIF record:");
            log(allrecords.values().toArray()[0].toString());
        }
        log("");
    }

    private void testVMRecords() throws Exception {
        announce("Get all the VM records");
        Map<VM, VM.Record> allrecords = VM.getAllRecords(connection);
        log("Got: " + allrecords.size() + " records");
        if (allrecords.size() > 0) {
            log("Printing out the first VM record:");
            log(allrecords.values().toArray()[0].toString());
        }
        log("");
    }
}