using System;
using System.Collections.Generic;
using System.Linq;
using System.Net.Http;
using System.Security.Cryptography;
using XenAPI;
using Console = System.Console; // XenAPI also defines a Console class

namespace XenServerWorkflows;

internal static partial class Workflows
{
    /// <summary>
    /// Upload data into a virtual disk, download the disk's raw contents and copy them into a second disk,
    /// then check that the copy matches. Disk contents travel as HTTP transfers alongside the API.
    /// </summary>
    /// <example>
    /// <code>
    /// Workflows.ExportImportVdi("https://xenserver", "root", password, "Shared NFS");
    /// </code>
    /// </example>
    /// <remarks>
    /// A disk's contents are not XenAPI calls: GET /export_raw_vdi reads them and PUT /import_raw_vdi writes
    /// them, both alongside the API with the session id in the query string. format=raw is every byte of the
    /// disk, so a raw export is as large as the disk's virtual size (format=vhd sends only the allocated
    /// blocks). Name a task in task_id to learn how the transfer ended: an HTTP 200 only means the server
    /// accepted the request.
    /// </remarks>
    public static void ExportImportVdi(string url, string user, string password, string srName)
    {
        var session = Connect(url, user, password);
        var sr = SrByName(session, srName);
        const long size = 8 * 1024 * 1024;

        XenRef<VDI> NewDisk(string name) => VDI.create(session, new VDI
        {
            name_label = name,
            SR = sr,
            virtual_size = size,
            type = vdi_type.user,
            sharable = false,
            read_only = false,
            other_config = new Dictionary<string, string>(),
        });

        // One raw transfer of a disk's contents, waiting for its task to finish.
        byte[] Transfer(HttpMethod method, string path, string vdi, byte[] data = null)
        {
            var task = Task.create(session, $"sdk-example-{path}", "").opaque_ref;
            try
            {
                using var client = InsecureHttpClient();
                using var request = new HttpRequestMessage(method,
                    $"{url}/{path}?session_id={session.opaque_ref}&task_id={task}&vdi={vdi}&format=raw");
                if (data != null) request.Content = new ByteArrayContent(data);
                using var response = client.Send(request);
                response.EnsureSuccessStatusCode();
                var body = response.Content.ReadAsByteArrayAsync().Result;

                while (Task.get_status(session, task) == task_status_type.pending)
                    System.Threading.Thread.Sleep(500);
                if (Task.get_status(session, task) != task_status_type.success)
                    throw new Exception($"{path} failed: {string.Join(", ", Task.get_error_info(session, task))}");
                return body;
            }
            finally
            {
                Task.destroy(session, task);
            }
        }

        var original = NewDisk("sdk-example-raw-source");
        var copy = NewDisk("sdk-example-raw-copy");
        try
        {
            var data = RandomNumberGenerator.GetBytes((int)size);
            Transfer(HttpMethod.Put, "import_raw_vdi", original, data);
            Console.WriteLine($"Uploaded {size / (1024 * 1024)} MiB into {VDI.get_name_label(session, original)}");

            var exported = Transfer(HttpMethod.Get, "export_raw_vdi", original);
            Console.WriteLine($"Downloaded {exported.Length / (1024 * 1024)} MiB of raw contents");

            Transfer(HttpMethod.Put, "import_raw_vdi", copy, exported);
            Console.WriteLine($"Copied them into {VDI.get_name_label(session, copy)}");

            var same = SHA256.HashData(Transfer(HttpMethod.Get, "export_raw_vdi", copy))
                .SequenceEqual(SHA256.HashData(data));
            Console.WriteLine($"The copy {(same ? "matches" : "DIFFERS FROM")} the original");
            if (!same) throw new Exception("the copied disk does not match the data uploaded");
        }
        finally
        {
            VDI.destroy(session, original);
            VDI.destroy(session, copy);
        }
        Console.WriteLine("OK: export-import-vdi");
        session.logout();
    }
}
