#!/usr/bin/env/python
#
# Copyright (c) Cloud Software Group, Inc.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
#
#   1) Redistributions of source code must retain the above copyright
#      notice, this list of conditions and the following disclaimer.
#
#   2) Redistributions in binary form must reproduce the above
#      copyright notice, this list of conditions and the following
#      disclaimer in the documentation and/or other materials
#      provided with the distribution.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
# "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
# LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS
# FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE
# COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT,
# INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
# (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
# SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
# HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT,
# STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
# ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED
# OF THE POSSIBILITY OF SUCH DAMAGE.

import time
import XenAPI
import parse_rrd

def print_latest_host_data(rrd_updates):
    host_uuid = rrd_updates.get_host_uuid()
    print "**********************************************************"
    print "Got values for Host: "+ host_uuid
    print "**********************************************************"

    for param in rrd_updates.get_host_param_list():
        if param != "":
            max_time=0
            data=""
            for row in range(rrd_updates.get_nrows()):
                 epoch = rrd_updates.get_row_time(row)
                 dv = str(rrd_updates.get_host_data(param,row))
                 if epoch > max_time:
                     max_time = epoch
                     data = dv
            nt = time.strftime("%H:%M:%S", time.localtime(max_time))
            print "%-30s             (%s , %s)" % (param, nt, data)


def print_latest_vm_data(rrd_updates, uuid):
    print "**********************************************************"
    print "Got values for VM: "+uuid
    print "**********************************************************"
    for param in rrd_updates.get_vm_param_list(uuid):
        if param != "":
            max_time=0
            data=""
            for row in range(rrd_updates.get_nrows()):
                epoch = rrd_updates.get_row_time(row)
                dv = str(rrd_updates.get_vm_data(uuid,param,row))
                if epoch > max_time:
                    max_time = epoch
                    data = dv
            nt = time.strftime("%H:%M:%S", time.localtime(max_time))
            print "%-30s             (%s , %s)" % (param, nt, data)

def build_vm_graph_data(rrd_updates, vm_uuid, param):
    time_now = int(time.time())
    for param_name in rrd_updates.get_vm_param_list(vm_uuid):
        if param_name == param:
            data = "#%s  Seconds Ago" % param
            for row in range(rrd_updates.get_nrows()):
                epoch = rrd_updates.get_row_time(row)
                data = str(rrd_updates.get_vm_data(vm_uuid, param_name, row))
                data += "\n%-14s %s" % (data, time_now - epoch)
            return data

def main():
    url = "https://<server>"
    session = XenAPI.Session(url)
    session.xenapi.login_with_password('root','<password>')

    rrd_updates = parse_rrd.RRDUpdates()
    params = {}
    params['cf'] = "AVERAGE"
    params['start'] = int(time.time()) - 10
    params['interval'] = 5
    params['host'] = ""
    rrd_updates.refresh(session.handle, params, url)

    if params['host'] == 'true':
        print_latest_host_data(rrd_updates)

    for uuid in rrd_updates.get_vm_list():
        print_latest_vm_data(rrd_updates, uuid)
        param = 'cpu0'
        data = build_vm_graph_data(rrd_updates, uuid, param)
        fh = open("%s-%s.dat" % (uuid, param), 'w')
        fh.write(data)
        fh.close()

main()