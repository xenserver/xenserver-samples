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

import java.util.Date;
import java.util.HashMap;
import java.util.Map;

import com.xensource.xenapi.Network;
import com.xensource.xenapi.SR;
import com.xensource.xenapi.Task;
import com.xensource.xenapi.Types;
import com.xensource.xenapi.VIF;
import com.xensource.xenapi.VM;

/**
 * Makes a new VM from a built-in template, starts and stops it.
 */
public class AsyncVMCreate extends TestBase {
    public String getTestName() {
        return "AsyncVMCreate";
    }

    protected void TestCore() throws Exception {
        /*First check we can start an HVM on the master*/
        checkMasterHvmCapable();

        VM template = getFirstWindowsTemplate();
        log("Template found: " + template.getNameLabel(connection));

        /* Clone the template */
        log("Cloning the template...");
        String vmName = new Date() + " (made by AsyncVMCreate.java)";
        Task cloning = template.createCloneAsync(connection, vmName);
        waitForTask(connection, cloning, 500);
        assertTaskSuccess(cloning);

        VM newVm = Types.toVM(cloning, connection);
        log("New VM clone: " + newVm.getNameLabel(connection));

        /* Find a storage repository */
        SR theSR = getStorage();
        log("Found SR: " + theSR.getNameLabel(connection));

        /* Find a network */
        Network network = getFirstNetwork();
        log("Network chosen: " + network.getNameLabel(connection));

        /* We have our clone and our network, attach them to each other with a VIF */
        makeVIF(newVm, network, "0");

        /* Now deliberately cause an error by creating a second VIF with the same parameters */

        log("Deliberately causing an error by trying to create the same VIF twice...");
        try{
            makeVIF(newVm, network, "0");
        }
        catch (Exception ex) {
            log("Task failed as expected");
        }

        /* Put the SR uuid into the provision XML */
        Map<String, String> otherConfig = newVm.getOtherConfig(connection);
        String disks = otherConfig.get("disks");
        disks = disks.replace("sr=\"\"", "sr=\"" + theSR.getUuid(connection) + "\"");
        otherConfig.put("disks", disks);
        newVm.setOtherConfig(connection, otherConfig);

        /* Now provision the disks */
        log("provisioning... ");
        Task provisioning = newVm.provisionAsync(connection);
        waitForTask(connection, provisioning, 5000);
        assertTaskSuccess(provisioning);
        log("provisioned");

        /* Should have done the trick. Let's see if it starts. */
        log("Starting new VM...");
        Task t = newVm.startAsync(connection, false, false);
        waitForTask(connection, t, 250);
        assertTaskSuccess(t);
        log("started");

        /* and shut it down */
        log("Shutting it down...");
        t = newVm.cleanShutdownAsync(connection);
        waitForTask(connection, t, 500);
        log("Shut down.");
    }

    /*
     * Create a VIF by making a VIF.record and then filling in the necessary fields
     */
    private void makeVIF(VM newVm, Network defaultNetwork, String device) throws Exception {
        VIF.Record newVifRecord = new VIF.Record();

        // These three parameters are used in the command line VIF creation
        newVifRecord.VM = newVm;
        newVifRecord.network = defaultNetwork;
        newVifRecord.device = device;

        // These appear to be necessary
        newVifRecord.MTU = 1500L;
        newVifRecord.lockingMode = Types.VifLockingMode.NETWORK_DEFAULT;
        newVifRecord.qosAlgorithmType = "";
        newVifRecord.qosAlgorithmParams = new HashMap<>();
        newVifRecord.otherConfig = new HashMap<>();

        /* Create the VIF by asynchronous means */
        log("Creating a VIF...");
        Task task1 = VIF.createAsync(connection, newVifRecord);
        waitForTask(connection, task1, 0);
        assertTaskSuccess(task1);
    }

    private void assertTaskSuccess(Task task) throws Exception {
        assert task.getStatus(connection) == Types.TaskStatusType.SUCCESS
                : "Task failed: " + task.getRecord(connection);
    }
}
