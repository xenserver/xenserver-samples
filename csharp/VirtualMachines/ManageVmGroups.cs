using System.Collections.Generic;
using XenAPI;
using Console = System.Console; // XenAPI also defines a Console class

namespace XenServerWorkflows;

internal static partial class Workflows
{
    /// <summary>
    /// Create an anti-affinity VM group, put a VM in it, read the membership back from the group side, then
    /// take the VM out again and delete the group.
    /// </summary>
    /// <example>
    /// <code>
    /// Workflows.ManageVmGroups("https://xenserver", "root", password, "web-01");
    /// </code>
    /// </example>
    public static void ManageVmGroups(string url, string user, string password,
        string vmName, string groupName = "sdk-example-group")
    {
        var session = Connect(url, user, password);
        var vmRef = VmByName(session, vmName);

        // anti_affinity asks the pool to keep the group's members on different hosts.
        var groupRef = VM_group.create(session, new VM_group
        {
            name_label = groupName,
            name_description = "Anti-affinity group created by the SDK example",
            placement = placement_policy.anti_affinity,
        });
        Console.WriteLine($"Created group:  {VM_group.get_uuid(session, groupRef)}");

        // Membership is written from the VM side...
        VM.set_groups(session, vmRef, new List<XenRef<VM_group>> { groupRef });

        // ...and read back from the group side, which is the half that is easy to get wrong.
        var members = VM_group.get_VMs(session, groupRef);
        Console.WriteLine($"Group members:  {members.Count}");
        foreach (var m in members)
            Console.WriteLine($"  {VM.get_name_label(session, m)}");

        // VM_group.destroy already clears the group from every member VM's groups field - no need to
        // remove membership ourselves first.
        VM_group.destroy(session, groupRef);
        Console.WriteLine("OK: manage-vm-groups");
        session.logout();
    }
}
