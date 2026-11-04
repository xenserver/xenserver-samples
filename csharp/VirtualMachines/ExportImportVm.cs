using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Net.Http;
using XenAPI;
using Console = System.Console; // XenAPI also defines a Console class

namespace XenServerWorkflows;

internal static partial class Workflows
{
    /// <summary>
    /// Export a VM to an XVA file and import it back as a new one. These are HTTP transfers alongside the API
    /// rather than API calls, so the session id travels in the query string.
    /// </summary>
    /// <example>
    /// <code>
    /// Workflows.ExportImportVm("https://xenserver", "root", password, "db-01");
    /// </code>
    /// </example>
    public static void ExportImportVm(string url, string user, string password, string vmName)
    {
        var session = Connect(url, user, password);

        // Name the VM: an export carries every block of its disks, so which VM matters (a large one
        // takes a long time, and fills the disk). Only a halted VM can be exported: its disks must not
        // be changing underneath the copy.
        var vm = VmByName(session, vmName);
        if (VM.get_power_state(session, vm) != vm_power_state.Halted)
            throw new Exception($"{vmName} must be halted to be exported");
        Console.WriteLine($"Exporting {vmName}");

        // Export and import are HTTP transfers alongside the API, not API calls, so the session id
        // travels in the query string.
        // A unique file, not a fixed name: an export is a real file on disk and two of them running at
        // once would otherwise fight over it.
        var path = Path.Combine(Path.GetTempPath(), $"sdk-example-export-{Guid.NewGuid():N}.xva");
        try
        {
            // Stream both directions: a real VM's export is gigabytes, too large to hold in memory.
            using (var client = InsecureHttpClient())
            {
                var uuid = VM.get_uuid(session, vm);
                using var response = client.GetAsync(
                    $"{url}/export?session_id={session.opaque_ref}&uuid={uuid}",
                    HttpCompletionOption.ResponseHeadersRead).Result;
                response.EnsureSuccessStatusCode();
                using (var httpStream = response.Content.ReadAsStreamAsync().Result)
                using (var fileStream = File.Create(path))
                    httpStream.CopyTo(fileStream);
            }
            Console.WriteLine($"  wrote {new FileInfo(path).Length / (1024.0 * 1024):F1} MiB to "
                              + $"{Path.GetFileName(path)}");

            // An XVA is a tar: ova.xml describes the VM, and the disk blocks follow in 1 MiB pieces, each
            // with its own checksum.
            var names = new List<string>();
            using (var reader = new System.Formats.Tar.TarReader(File.OpenRead(path)))
                while (reader.GetNextEntry() is { } entry) names.Add(entry.Name);
            Console.WriteLine($"  archive holds {names[0]} and "
                              + $"{names.Count(n => !n.EndsWith(".checksum")) - 1} disk block(s)");

            // The imported VM's ref is NOT in the /import response body on a real host. Create a task
            // first, append &task_id=<task> to the /import URL, poll the task, and parse the ref out
            // of task.get_result() (same <value>...</value> string-strip wait-for-task already uses).
            var task = Task.create(session, "vm_import", $"importing {vmName} back").opaque_ref;
            string imported;
            try
            {
                using (var client = InsecureHttpClient())
                using (var fileStream = File.OpenRead(path))
                {
                    var response = client.PutAsync(
                        $"{url}/import?session_id={session.opaque_ref}&task_id={task}",
                        new StreamContent(fileStream)).Result;
                    response.EnsureSuccessStatusCode();
                }

                while (Task.get_status(session, task) == task_status_type.pending)
                    System.Threading.Thread.Sleep(500);
                if (Task.get_status(session, task) != task_status_type.success)
                    throw new Exception($"import failed: {string.Join(", ", Task.get_error_info(session, task))}");
                // The result lists the imported VMs (<value><array><data>OpaqueRef:...</data></array></value>
                // on a real host), so take the first reference in it.
                imported = System.Text.RegularExpressions.Regex.Match(
                    Task.get_result(session, task), "OpaqueRef:[^<]+").Value;
            }
            finally
            {
                Task.destroy(session, task);
            }
            Console.WriteLine($"  imported as {VM.get_name_label(session, imported)}");

            DestroyVmAndDisks(session, imported);
            Console.WriteLine("OK: export-import-vm");
        }
        finally
        {
            // Always clean up the file, on failure too: a real export is gigabytes, not worth leaving
            // behind in %TEMP%.
            File.Delete(path);
        }
        session.logout();
    }
}
