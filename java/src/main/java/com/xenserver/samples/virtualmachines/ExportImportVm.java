package com.xenserver.samples.virtualmachines;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.Session;
import com.xensource.xenapi.Task;
import com.xensource.xenapi.Types;
import com.xensource.xenapi.VM;

import org.apache.hc.client5.http.classic.methods.HttpGet;
import org.apache.hc.client5.http.classic.methods.HttpPut;
import org.apache.hc.client5.http.impl.classic.CloseableHttpClient;
import org.apache.hc.core5.http.io.entity.EntityUtils;

import static com.xenserver.samples.Helpers.destroyVmAndDisks;
import static com.xenserver.samples.Helpers.vmByName;
import static com.xenserver.samples.PoolConnection.connect;
import static com.xenserver.samples.PoolConnection.trustingHttpClient;

public final class ExportImportVm {
    private ExportImportVm() {
    }

    /**
     * Export and import a VM.
     *
     * <p>Export a VM to an XVA file and import it back as a new one. These are HTTP transfers alongside
     * the API rather than API calls, so the session id travels in the query string.
     *
     * <p>Run it:
     *
     * <pre>{@code
     * ExportImportVm.run("https://xenserver", "root", password, "db-01");
     * }</pre>
     */
    public static void run(String url, String user, String password, String vmName) throws Exception {
        Connection conn = connect(url, user, password);
        try {
            // Name the VM: an export carries every block of its disks, so which VM matters (a large one
            // takes a long time, and fills the disk). Only a halted VM can be exported: its disks must
            // not be changing underneath the copy.
            VM vm = vmByName(conn, vmName);
            if (vm.getPowerState(conn) != Types.VmPowerState.HALTED)
                throw new RuntimeException(vmName + " must be halted to be exported");
            System.out.println("Exporting " + vmName);

            // Export and import are HTTP transfers alongside the API, not API calls, so the session id
            // travels in the query string.
            String session = conn.getSessionReference();
            java.io.File file = java.io.File.createTempFile("sdk-example-export", ".xva");
            try {
                // Stream both directions: a real VM's export is gigabytes, too large to hold in memory.
                HttpGet get = new HttpGet(url + "/export?session_id=" + session + "&uuid=" + vm.getUuid(conn));
                try (CloseableHttpClient http = trustingHttpClient()) {
                    http.execute(get, resp -> {
                        try (java.io.InputStream in = resp.getEntity().getContent()) {
                            java.nio.file.Files.copy(in, file.toPath(),
                                java.nio.file.StandardCopyOption.REPLACE_EXISTING);
                        }
                        return null;
                    });
                }
                System.out.printf("  wrote %.1f MiB to %s%n", file.length() / (1024.0 * 1024), file.getName());

                // An XVA is a tar: ova.xml describes the VM, and the disk blocks follow in 1 MiB pieces,
                // each with its own checksum.
                java.util.List<String> names = tarNames(file);
                long blocks = names.stream().filter(n -> !n.endsWith(".checksum")).count() - 1;
                System.out.printf("  archive holds %s and %d disk block(s)%n", names.get(0), blocks);

                // The imported VM's ref is NOT in the /import response body on a real host. Create a
                // task first, append &task_id=<task> to the /import URL, poll the task, and parse the
                // ref out of task.getResult() (same <value>...</value> string-strip wait-for-task
                // already uses). Destroy the task in a finally.
                Task task = Task.create(conn, "vm_import", "importing " + vmName + " back");
                VM importedVm;
                try {
                    HttpPut put = new HttpPut(
                        url + "/import?session_id=" + session + "&task_id=" + task.toWireString());
                    put.setEntity(new org.apache.hc.core5.http.io.entity.FileEntity(
                        file, org.apache.hc.core5.http.ContentType.APPLICATION_OCTET_STREAM));
                    try (CloseableHttpClient http = trustingHttpClient()) {
                        http.execute(put, resp -> EntityUtils.toString(resp.getEntity()));
                    }

                    while (task.getStatus(conn) == Types.TaskStatusType.PENDING) Thread.sleep(500);
                    if (task.getStatus(conn) != Types.TaskStatusType.SUCCESS)
                        throw new RuntimeException("import failed: " + task.getErrorInfo(conn));
                    // The result lists the imported VMs (<value><array><data>OpaqueRef:...</data></array></value>
                    // on a real host), so take the first reference in it.
                    java.util.regex.Matcher ref = java.util.regex.Pattern.compile("OpaqueRef:[^<]+")
                        .matcher(task.getResult(conn));
                    if (!ref.find()) throw new RuntimeException("import returned no VM: " + task.getResult(conn));
                    importedVm = new VM(ref.group());
                } finally {
                    task.destroy(conn);
                }
                System.out.println("  imported as " + importedVm.getNameLabel(conn));

                // The import brought its own disks along; destroy those too, not just the VM record.
                destroyVmAndDisks(conn, importedVm);
                System.out.println("OK: export-import-vm");
            } finally {
                // Always clean up the file, on failure too: a real export is gigabytes, not worth
                // leaving behind in %TEMP%.
                file.delete();
            }
        } finally {
            Session.logout(conn);
        }
    }

    /**
     * The names of a tar archive's entries.
     *
     * <p>Read with the format's own layout rather than a library: the name is the first 100 bytes of each
     * 512-byte header, the size is octal at offset 124, and every file is padded up to the next 512-byte
     * boundary. Small enough to do here, and it keeps the example free of another dependency.
     */
    private static java.util.List<String> tarNames(java.io.File file) throws Exception {
        java.util.List<String> names = new java.util.ArrayList<>();
        try (java.io.DataInputStream in = new java.io.DataInputStream(
                new java.io.BufferedInputStream(new java.io.FileInputStream(file)))) {
            byte[] header = new byte[512];
            while (in.read(header) == 512) {
                String name = new String(header, 0, 100, java.nio.charset.StandardCharsets.US_ASCII)
                    .trim().replace("\0", "");
                if (name.isEmpty()) break;                      // the end-of-archive marker
                names.add(name);
                String octal = new String(header, 124, 12, java.nio.charset.StandardCharsets.US_ASCII)
                    .trim().replace("\0", "");
                long size = octal.isEmpty() ? 0 : Long.parseLong(octal, 8);
                in.skipBytes((int) ((size + 511) / 512 * 512));
            }
        }
        return names;
    }
}
