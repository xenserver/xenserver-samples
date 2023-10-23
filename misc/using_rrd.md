# XenServer Operational Metrics

This short tutorial explains the basic parts of [print_host_and_vm_rrd.py](print_host_and_vm_rrd.py), an example script demonstrating how to download, parse, and use the operational metrics that are stored in a RRD database on a XenServer host.

The script [print_host_and_vm_rrd.py](print_host_and_vm_rrd.py) uses the XenServer Python module `XenAPI.py` for querying the HTTP(S) interface of the XenServer host, and the example python script [parse_rrd.py](parse_rrd.py) for parsing the `xport` XML that is returned from the query.

## Getting the latest RRD datapoints

First we need to import both the XenAPI and the [parse_rrd.py](parse_rrd.py) libraries into the python script.

```shell
#!/usr/bin/env/python
import XenAPI
import parse_rrd
```

In order to download RRD updates, we need to create a XenAPI Session and pass the Session opaque reference in the request as a query parameter. To authenticate against the target XenSever host we use the XenAPI's call `login_with_password`.

```python
def main():
    url = "https://<server>"
    session = XenAPI.Session(url)
    session.xenapi.login_with_password('root','<password>')
```

Then we create a RRD object and fill it with data. In the following snippet, the `params` array is overriding the default parameters specified in [parse_rrd.py](parse_rrd.py). Note that, if no url is specified, [parse_rrd.py](parse_rrd.py) uses `https://localhost` by default.

```python
    rrd_updates = parse_rrd.RRDUpdates()
    params = {}
    params['cf'] = "AVERAGE"
    params['start'] = int(time.time()) - 10 #This is for the purposes of this tutorial
    params['interval'] = 5
    params['host'] = ""
    rrd_updates.refresh(session.handle, params, url)
```

It is then very easy to make use of the calls provided in [parse_rrd.py](parse_rrd.py) to extract and search through the downloaded data. You can see from the code below that for getting VM data we need only specify the VM's `uuid`, the metric we want to get, and the row we're interested in. This method loops through all the metrics for a given VM and returns only the most recent value for each metric.

```python
def print_latest_vm_data(rrd_updates, uuid):
    print "**********************************************************"
    print "Got values for VM: "+ uuid
    print "**********************************************************"
    for param in rrd_updates.get_vm_param_list(uuid):
        if param != "":
            max_time = 0
            data=""
            for row in range(rrd_updates.get_nrows()):
                epoch = rrd_updates.get_row_time(row)
                dv = str(rrd_updates.get_vm_data(uuid,param,row))
                if epoch > max_time:
                    max_time = epoch
                    data = dv
            nt = time.strftime("%H:%M:%S", time.localtime(max_time))
            print "%-30s (%s , %s)" % (param, nt, data)
```

The script [print_host_and_vm_rrd.py](print_host_and_vm_rrd.py) contains also a similar method for printing host data. Note that, in order to download RRD updates for the host, we need to specify it in the `params` array:

```python
    params['host'] = 'true'
```

The result of running this method on every VM present on the target host will produce something similar to this:

```
**********************************************************
Got values for VM: cafd67c3-ede7-4257-99bb-84d5b6756bb1
**********************************************************
vbd_xvdb_write                             (12:15:00 , 0.0)
memory_target                              (12:15:00 , 412090368.0)
vbd_xvdb_read                              (12:15:00 , 0.0)
cpu6                                       (12:15:00 , 0.0)
cpu7                                       (12:15:00 , 0.0)
cpu4                                       (12:15:00 , 0.0)
cpu5                                       (12:15:00 , 0.0)
cpu2                                       (12:15:00 , 0.0089)
cpu3                                       (12:15:00 , 0.002)
cpu0                                       (12:15:00 , 0.0104)
cpu1                                       (12:15:00 , 0.0034)
vbd_xvda_write                             (12:15:00 , 0.0)
vbd_xvda_read                              (12:15:00 , 0.0)
memory                                     (12:15:00 , 412090368.0)
**********************************************************
Got values for VM: a9a488ec-2cb4-3ff3-77be-8d8cc453e32f
**********************************************************
vbd_xvdb_write                             (12:15:00 , 0.0)
memory_target                              (12:15:00 , 268435456.0)
vbd_xvdb_read                              (12:15:00 , 0.0)
memory_internal_free                       (12:15:00 , 113700.0)
memory                                     (12:15:00 , 268435456.0)
vbd_xvda_write                             (12:15:00 , 808.2336)
cpu0                                       (12:15:00 , 0.0014)
vif_0_tx                                   (12:15:00 , 0.0)
vbd_xvda_read                              (12:15:00 , 0.0)
vif_1_tx                                   (12:15:00 , 0.0)
vif_0_rx                                   (12:15:00 , 475.4616)
vif_1_rx                                   (12:15:00 , 0.0)
```

## Plotting the RRD data

An easy way to plot the RRD data is by using the [Gnuplot](http://www.gnuplot.info/) utility.

Create a method that outputs the RRD metric data in a format acceptable to Gnuplot. (We are printing out a single data point per row, separating the time and value columns with whitespace.)

```python
def build_vm_graph_data(rrd_updates, vm_uuid, param):
    time_now = int(time.time())
    for param_name in rrd_updates.get_vm_param_list(vm_uuid):
        if param_name == param:
            data = "#%s Seconds Ago" % param
            for row in range(rrd_updates.get_nrows()):
                epoch = rrd_updates.get_row_time(row)
                data = str(rrd_updates.get_vm_data(vm_uuid, param_name, row))
                data += "\n%-14s %s" % (data, time_now - epoch)
            return data
```

Call this method and save the result to a file. In this example we will be plotting the metrics for 'cpu0'.

```python
    for uuid in rrd_updates.get_vm_list():
        param = 'cpu0'
        data = build_vm_graph_data(rrd_updates, uuid, param)
        fh = open("%s-%s.dat" % (uuid, param), 'w')
        fh.write(data)
        fh.close()
```

Now use Gnuplot to import this data file and plot a graph

```shell
gnuplot
```

Note: You can supply the following as an argument to Gnuplot which would help you to automate the process of creating graphs in an easier way

```shell
set xlabel "Seconds Ago"
set ylabel "CPU Utilisation"
plot <DATAFILE.dat> using 0:1 title 'cpu0' with linespoints
```

This should then produce a plot similar this one:

![RRD plot](/misc/media/rrd_plot.png)