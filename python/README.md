# XenServer Python examples

This folder holds the Python version of every workflow example ([the full list](../README.md#workflow-examples)),
one module per workflow, in a package per area:

```
python/
  getting_started/connect_inventory.py, events.py, error_handling.py, trace_api_calls.py, ...
  virtual_machines/create_vm.py, clone_vm.py, snapshot_revert.py, ...
  storage/  networking/  migration/  hosts_and_pools/  updates/  ...
  connection.py    connecting to a pool (used by every workflow)
  helpers.py       small helpers several workflows share (find by name, clean up, ...)
  workflows.py     the command-line dispatcher that runs any workflow by name
```

## Run

You need Python 3 and the SDK's `XenAPI` module, either from PyPI or by copying
`XenServerPython/XenAPI.py` from the SDK into this folder:

```
pip install -r requirements.txt
python workflows.py connect-inventory https://xenserver root <password>
```

## Use a workflow in your own code

Each workflow is a self-contained function you can copy into your own code, together with
`connection.py` (and any helper from `helpers.py` it imports). Its module docstring describes what it
does and shows how to call it, e.g.:

```python
from getting_started.connect_inventory import connect_inventory

connect_inventory("https://xenserver", "root", password)
```
