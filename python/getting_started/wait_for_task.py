"""Drive an asynchronous task.

Start a long-running operation asynchronously to get a task back immediately, then poll it to
completion and read its result — how to drive operations without blocking.

Run it::

    wait_for_task("https://xenserver", "root", password, "Rocky Linux 8")
"""

import time

from connection import connect
from helpers import template_by_name


def wait_for_task(url, username, password, template_name, new_vm_name="sdk-example-asynctask"):
    """Every message has an Async.* twin that returns a Task ref immediately; poll it to completion."""
    session = connect(url, username, password)
    task = session.xenapi.Async.VM.clone(template_by_name(session, template_name), new_vm_name)
    print("Started task: %s" % session.xenapi.task.get_uuid(task))

    while session.xenapi.task.get_status(task) == "pending":
        print("  progress: %.0f%%" % (session.xenapi.task.get_progress(task) * 100))
        time.sleep(0.2)
    print("Task status: %s" % session.xenapi.task.get_status(task))

    # The result of an object-creating task is <value>OpaqueRef:...</value>.
    result = session.xenapi.task.get_result(task)
    vm_ref = result.replace("<value>", "").replace("</value>", "").strip()
    print("Task produced VM: %s" % session.xenapi.VM.get_name_label(vm_ref))

    # Tidy up.
    session.xenapi.VM.destroy(vm_ref)
    session.xenapi.task.destroy(task)
    print("OK: wait-for-task")
    session.xenapi.session.logout()
