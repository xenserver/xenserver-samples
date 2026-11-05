using System;
using System.Collections.Generic;
using XenAPI;
using Console = System.Console; // XenAPI also defines a Console class

namespace XenServerWorkflows;

internal static partial class Workflows
{
    /// <summary>
    /// Provision a VM from a template and assign it a virtual GPU: find a GPU group that offers a vGPU type,
    /// attach it, and read the assignment back.
    /// </summary>
    /// <example>
    /// <code>
    /// Workflows.CreateVmWithVgpu("https://xenserver", "root", password, "Rocky Linux 8");
    /// </code>
    /// </example>
    public static void CreateVmWithVgpu(string url, string user, string password,
        string templateName, string newVmName = "sdk-example-vgpu-vm")
    {
        var session = Connect(url, user, password);
        // Find a GPU group that offers a real (non-passthrough) vGPU type, plus that type.
        var (groupRef, typeRef) = GpuGroupWithVgpuType(session);
        var typeRec = VGPU_type.get_record(session, typeRef);
        Console.WriteLine($"Using vGPU type: {typeRec.model_name} ({typeRec.framebuffer_size / (1024 * 1024)} MB framebuffer)");

        // Provision a fresh VM from the template to attach the vGPU to.
        var templateRef = TemplateByName(session, templateName);
        var vmRef = VM.clone(session, templateRef, newVmName).opaque_ref;
        Provision(session, vmRef);

        // Assign the vGPU: device "0" is the VM's first vGPU slot, other_config is empty.
        var vgpuRef = VGPU.create(session, vmRef, groupRef, "0", new Dictionary<string, string>(), typeRef).opaque_ref;
        Console.WriteLine($"Created vGPU: {VGPU.get_uuid(session, vgpuRef)}");

        // Read the assignment back.
        var vgpus = VM.get_VGPUs(session, vmRef);
        var assigned = VGPU_type.get_model_name(session, VGPU.get_type(session, vgpus[0].opaque_ref).opaque_ref);
        Console.WriteLine($"VM now has {vgpus.Count} vGPU(s); type = {assigned}");

        // Tidy up so the example is repeatable.
        VGPU.destroy(session, vgpuRef);
        DestroyVmAndDisks(session, vmRef);
        Console.WriteLine("Cleaned up the example VM and its vGPU.");
        Console.WriteLine("OK: create-vm-with-vgpu");
        session.logout();
    }

    /// <summary>Find a (GPU_group, VGPU_type) pair where the group offers a non-passthrough vGPU
    /// type.</summary>
    private static (string, string) GpuGroupWithVgpuType(Session session)
    {
        foreach (var (groupRef, group) in GPU_group.get_all_records(session))
        {
            if (group.PGPUs.Count == 0) continue;
            foreach (var typeRef in group.supported_VGPU_types)
                if (VGPU_type.get_model_name(session, typeRef.opaque_ref) != "passthrough")
                    return (groupRef.opaque_ref, typeRef.opaque_ref);
        }
        throw new Exception("no GPU group offers a vGPU type");
    }
}
