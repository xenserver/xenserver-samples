using System;
using System.IO;
using System.Linq;
using System.Net.Http;
using XenAPI;
using Console = System.Console; // XenAPI also defines a Console class

namespace XenServerWorkflows;

internal static partial class Workflows
{
    /// <summary>
    /// Download a host's configuration backup and verify it downloaded; optionally stage it back onto that
    /// same host's backup partition, ready for a restore done from the installer.
    /// </summary>
    /// <example>
    /// <code>
    /// Workflows.BackupHostConfig("https://xenserver", "root", password);
    /// </code>
    /// </example>
    /// <remarks>
    /// Both /host_backup and /host_restore are served only by whichever host physically accepted the HTTP
    /// connection - the handler is keyed off the connection's own address, not any ref= in the query string.
    /// So backing up/restoring a host means opening the connection to THAT host's own address, not the pool's
    /// (coordinator) url. ref= is kept in the query string for readability in the host's logs.
    /// </remarks>
    public static void BackupHostConfig(string url, string user, string password, bool restore = false)
    {
        var session = Connect(url, user, password);

        // The coordinator: always reachable at the pool's address. (Back up every host, in practice.)
        var host = Pool.get_master(session, Pool.get_all(session)[0]);
        var hostUrl = HostUrl(url, Host.get_address(session, host));
        Console.WriteLine($"Backing up {Host.get_name_label(session, host)}");

        // Stream it: a real host's backup can be hundreds of MB, too large to hold in memory (and,
        // unlike Python's binding, each XenAPI call below opens its own fresh HttpClient - see
        // RestoreHostConfig - so there's no idle keep-alive connection here that needs dropping first).
        var path = Path.Combine(Path.GetTempPath(), $"sdk-example-host-{Guid.NewGuid():N}.backup");
        using (var client = InsecureHttpClient())
        {
            using var response = client.GetAsync(
                $"{hostUrl}/host_backup?session_id={session.opaque_ref}&ref={host.opaque_ref}",
                HttpCompletionOption.ResponseHeadersRead).Result;
            response.EnsureSuccessStatusCode();
            using (var httpStream = response.Content.ReadAsStreamAsync().Result)
            using (var fileStream = File.Create(path))
                httpStream.CopyTo(fileStream);
        }
        var size = new FileInfo(path).Length;
        if (size == 0) throw new InvalidOperationException($"{path} came back empty");
        Console.WriteLine($"  wrote {size} bytes to {Path.GetFileName(path)}");

        var name = Host.get_name_label(session, host);
        if (restore)
        {
            // host-restore does not restore the host there and then: it only writes the archive over that
            // host's currently inactive backup partition, ready for the next boot. It takes effect only
            // once that host is booted from the installer and Restore is chosen there.
            RestoreHostConfig(session, hostUrl, host, path);
            Console.WriteLine($"  staged it on {name}'s backup partition - it takes effect only after "
                              + "booting that host from the installer and choosing Restore");
        }
        else
        {
            Console.WriteLine($"  not restoring it (pass restore=true to stage it on {name}'s backup partition)");
        }

        File.Delete(path);
        Console.WriteLine("OK: backup-host-config");
        session.logout();
    }

    /// <summary>
    /// Build the URL for a given host's own address, keeping the scheme and port the caller originally
    /// connected with (a host's management address carries no port of its own).
    /// </summary>
    private static string HostUrl(string url, string address)
    {
        var uri = new Uri(url);
        var port = uri.IsDefaultPort ? "" : $":{uri.Port}";
        return $"{uri.Scheme}://{address}{port}";
    }

    /// <summary>
    /// Upload a backup to a host - over a connection opened to THAT host's own address - and throw if
    /// the task reports it was refused.
    /// </summary>
    /// <remarks>
    /// An upload answers 200 as soon as it has read the request headers, because the client waits for that
    /// before it starts sending the file. The outcome therefore cannot be in the status line: it arrives on
    /// a task you create first, name in the URL, and poll once the upload has finished.
    /// </remarks>
    private static void RestoreHostConfig(Session session, string hostUrl, XenRef<Host> host, string path)
    {
        var task = Task.create(session, "host_restore", "restoring a configuration backup").opaque_ref;
        try
        {
            // Stream the upload too, rather than reading the whole backup into memory first. Every
            // XenAPI call this binding makes (including task.create/get_status below) opens a brand new
            // HttpClient and tears it down again - unlike Python's single long-lived xmlrpc.client
            // connection, there is no idle keep-alive connection here left over from the transfer that
            // would need to be dropped before the next call.
            using (var client = InsecureHttpClient())
            using (var fileStream = File.OpenRead(path))
            {
                var response = client.PutAsync(
                    $"{hostUrl}/host_restore?session_id={session.opaque_ref}&ref={host.opaque_ref}&task_id={task}",
                    new StreamContent(fileStream)).Result;
                response.EnsureSuccessStatusCode();
            }

            while (Task.get_status(session, task) == task_status_type.pending)
                System.Threading.Thread.Sleep(500);
            if (Task.get_status(session, task) != task_status_type.success)
                throw new InvalidOperationException($"refused ({Task.get_error_info(session, task).Last()})");
        }
        finally
        {
            Task.destroy(session, task);
        }
    }
}
