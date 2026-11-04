using System.Collections.Generic;
using XenAPI;
using Console = System.Console; // XenAPI also defines a Console class

namespace XenServerWorkflows;

internal static partial class Workflows
{
    /// <summary>
    /// Set a VM's vCPU counts and boot order, then read them back.
    /// </summary>
    /// <example>
    /// <code>
    /// Workflows.VmBootConfig("https://xenserver", "root", password, "Rocky Linux 8");
    /// </code>
    /// </example>
    public static void VmBootConfig(string url, string user, string password,
        string templateName, string newVmName = "sdk-example-boot")
    {
        var session = Connect(url, user, password);
        var vm = VM.clone(session, TemplateByName(session, templateName), newVmName).opaque_ref;
        Provision(session, vm);

        VM.set_VCPUs_max(session, vm, 4);
        VM.set_VCPUs_at_startup(session, vm, 2);
        Console.WriteLine($"vCPUs: {VM.get_VCPUs_at_startup(session, vm)}/{VM.get_VCPUs_max(session, vm)}");

        // Boot mode: firmware ("bios"/"uefi") lives in HVM_boot_params; Secure Boot in
        // platform["secureboot"]. "auto" (not a hard-coded "true") is the real xe/XenCenter convention:
        // xapi resolves it against whether the pool actually holds Secure Boot certificates, at
        // VM.start time - a hard "true" would claim Secure Boot is on even on a template that was never
        // set up for it, since set_platform does no validation of its own.
        VM.set_HVM_boot_params(session, vm, new Dictionary<string, string> { ["order"] = "cdn", ["firmware"] = "uefi" });
        var platform = VM.get_platform(session, vm);
        platform["secureboot"] = "auto";
        VM.set_platform(session, vm, platform);
        Console.WriteLine($"Boot order: {VM.get_HVM_boot_params(session, vm)["order"]}");
        Console.WriteLine($"Boot mode: firmware={VM.get_HVM_boot_params(session, vm)["firmware"]}, " +
                          $"secureboot={VM.get_platform(session, vm)["secureboot"]} " +
                          "(resolved against pool certificates at boot)");

        DestroyVmAndDisks(session, vm);
        Console.WriteLine("OK: vm-boot-config");
        session.logout();
    }
}
