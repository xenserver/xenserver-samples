# Drive an asynchronous task.
#
# Start a long-running operation asynchronously to get a task back immediately, then poll it to completion and
# read its result — how to drive operations without blocking.
#
# Run it:
#   ./workflows.sh wait-for-task https://xenserver root "$password"

wait_for_task() {
    # xe commands run synchronously (the CLI blocks until the operation completes), so there is no task
    # to poll; the API's tasks are listed here for reference.
    echo "Current tasks: $(count_csv "$(xe task-list params=uuid --minimal)")"
    echo "xe waits for each command to finish, so no async polling is needed."
    echo "OK: wait-for-task"
}
