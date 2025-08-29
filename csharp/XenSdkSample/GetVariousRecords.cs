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

using System.Linq;
using XenAPI;


namespace XenSdkSample
{
    class GetVariousRecords : TestBase
    {
        public GetVariousRecords(OutputLogger logger, Session session)
            : base(logger, session)
        {
        }

        public override string Name => "GetVariousRecords";

        protected override string Description => "Print records for various API objects";

        protected override void TestCore()
        {
            PrintHostRecords(Session);
            PrintStorageRepositories(Session);
            PrintVmRecords(Session);
            PrintPhysicalNetworkInterfaces(Session);
        }

        private void PrintHostRecords(Session session)
        {
            Logger.Log("Hosts");
            Logger.WriteHRule();

            var hostRecords = Host.get_all_records(session);
            foreach (var hostRec in hostRecords)
            {
                var host = hostRec.Value;
                Logger.Log("Name: {0}", host.name_label);
                Logger.Log("Hostname: {0}", host.hostname);
                Logger.Log("Description: {0}", host.name_description);
                Logger.WriteLine();
            }
        }

        private void PrintStorageRepositories(Session session)
        {
            Logger.Log("Storage Repositories");
            Logger.WriteHRule();

            var srRecords = SR.get_all_records(session);
            foreach (var srRec in srRecords)
            {
                var sr = srRec.Value;
                Logger.Log("Name: {0}", sr.name_label);
                Logger.Log("Description: {0}", sr.name_description);
                Logger.Log("Usage: {0:0.0}GB / {1:0.0}GB", sr.physical_utilisation / 1e9, sr.physical_size / 1e9);
                Logger.WriteLine();
            }
        }

        private void PrintVmRecords(Session session)
        {
            Logger.Log("Virtual Machines");
            Logger.WriteHRule();

            var vmRecords = VM.get_all_records(session);
            foreach (var vmRec in vmRecords)
            {
                var vm = vmRec.Value;
                Logger.Log(vm.is_a_template ? "VM name: {0}" : "Template name {0}", vm.name_label);
                Logger.Log("Power state: {0}", vm.power_state);
                string ops = string.Join(",", vm.allowed_operations.Select(op => op.ToString()));
                Logger.Log("Allowed operations: {0}", ops);
                Logger.Log("vCPUs: {0}", vm.VCPUs_at_startup);
                Logger.WriteLine();
            }
        }

        private void PrintPhysicalNetworkInterfaces(Session session)
        {
            Logger.Log("Physical network interfaces");
            Logger.WriteHRule();

            var pifRecords = PIF.get_all_records(session);
            foreach (var pifRec in pifRecords)
            {
                var pif = pifRec.Value;
                Host host = Host.get_record(session, pif.host);
                Logger.Log("Host: {0}", host.name_label);
                Logger.Log("IP: {0}", pif.IP);
                Logger.Log("MAC address: {0}", pif.MAC);
                Logger.WriteLine();
            }
        }
    }
}
