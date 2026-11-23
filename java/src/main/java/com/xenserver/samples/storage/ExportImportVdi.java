package com.xenserver.samples.storage;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.SR;
import com.xensource.xenapi.Session;
import com.xensource.xenapi.Task;
import com.xensource.xenapi.Types;
import com.xensource.xenapi.VDI;

import org.apache.hc.client5.http.classic.methods.HttpGet;
import org.apache.hc.client5.http.classic.methods.HttpPut;
import org.apache.hc.client5.http.classic.methods.HttpUriRequestBase;
import org.apache.hc.client5.http.impl.classic.CloseableHttpClient;
import org.apache.hc.core5.http.io.entity.ByteArrayEntity;
import org.apache.hc.core5.http.io.entity.EntityUtils;

import java.security.MessageDigest;
import java.security.SecureRandom;
import java.util.Arrays;
import java.util.HashMap;

import static com.xenserver.samples.Helpers.srByName;
import static com.xenserver.samples.PoolConnection.connect;
import static com.xenserver.samples.PoolConnection.trustingHttpClient;

public final class ExportImportVdi {
    private ExportImportVdi() {
    }

    private static final long SIZE = 8L * 1024 * 1024;
    private static final SecureRandom RANDOM = new SecureRandom();

    /**
     * Copy a disk's contents.
     *
     * <p>Upload data into a virtual disk, download the disk's raw contents and copy them into a second disk,
     * then check that the copy matches. Disk contents travel as HTTP transfers alongside the API.
     *
     * <p>A disk's contents are not XenAPI calls: GET /export_raw_vdi reads them and PUT /import_raw_vdi
     * writes them, both alongside the API with the session id in the query string. format=raw is every
     * byte of the disk, so a raw export is as large as the disk's virtual size (format=vhd sends only the
     * allocated blocks). Name a task in task_id to learn how the transfer ended: an HTTP 200 only means the
     * server accepted the request.
     *
     * <p>Run it:
     *
     * <pre>{@code
     * ExportImportVdi.run("https://xenserver", "root", password, "Shared NFS");
     * }</pre>
     */
    public static void run(String url, String user, String password, String srName) throws Exception {
        Connection conn = connect(url, user, password);
        SR sr = srByName(conn, srName, false);

        VDI original = null;
        VDI copy = null;
        try {
            original = newDisk(conn, sr, "sdk-example-raw-source");
            copy = newDisk(conn, sr, "sdk-example-raw-copy");
            byte[] data = new byte[(int) SIZE];
            RANDOM.nextBytes(data);
            transfer(conn, url, new HttpPut(url), "import_raw_vdi", original, data);
            System.out.printf("Uploaded %d MiB into %s%n", SIZE / (1024 * 1024), original.getNameLabel(conn));

            byte[] exported = transfer(conn, url, new HttpGet(url), "export_raw_vdi", original, null);
            System.out.printf("Downloaded %d MiB of raw contents%n", exported.length / (1024 * 1024));

            transfer(conn, url, new HttpPut(url), "import_raw_vdi", copy, exported);
            System.out.println("Copied them into " + copy.getNameLabel(conn));

            MessageDigest sha256 = MessageDigest.getInstance("SHA-256");
            boolean same = Arrays.equals(
                sha256.digest(transfer(conn, url, new HttpGet(url), "export_raw_vdi", copy, null)),
                sha256.digest(data));
            System.out.println("The copy " + (same ? "matches" : "DIFFERS FROM") + " the original");
            if (!same) throw new IllegalStateException("the copied disk does not match the data uploaded");
        } finally {
            if (original != null) original.destroy(conn);
            if (copy != null) copy.destroy(conn);
        }
        System.out.println("OK: export-import-vdi");
        Session.logout(conn);
    }

    private static VDI newDisk(Connection conn, SR sr, String name) throws Exception {
        VDI.Record record = new VDI.Record();
        record.nameLabel = name;
        record.SR = sr;
        record.virtualSize = SIZE;
        record.type = Types.VdiType.USER;
        record.sharable = false;
        record.readOnly = false;
        record.otherConfig = new HashMap<>();
        return VDI.create(conn, record);
    }

    /** One raw transfer of a disk's contents, waiting for its task to finish. */
    private static byte[] transfer(Connection conn, String url, HttpUriRequestBase request, String path, VDI vdi,
                                   byte[] data) throws Exception {
        Task task = Task.create(conn, "sdk-example-" + path, "");
        try {
            request.setUri(new java.net.URI(String.format("%s/%s?session_id=%s&task_id=%s&vdi=%s&format=raw",
                url, path, conn.getSessionReference(), task.toWireString(), vdi.toWireString())));
            if (data != null) request.setEntity(new ByteArrayEntity(data, null));
            byte[] body;
            try (CloseableHttpClient http = trustingHttpClient()) {
                body = http.execute(request, response -> {
                    byte[] received = EntityUtils.toByteArray(response.getEntity());
                    if (response.getCode() < 200 || response.getCode() >= 300) {
                        throw new IllegalStateException(path + ": HTTP " + response.getCode() + ": "
                            + new String(received, java.nio.charset.StandardCharsets.UTF_8));
                    }
                    return received;
                });
            }
            while (task.getStatus(conn) == Types.TaskStatusType.PENDING) Thread.sleep(500);
            if (task.getStatus(conn) != Types.TaskStatusType.SUCCESS)
                throw new IllegalStateException(path + " failed: " + task.getErrorInfo(conn));
            return body;
        } finally {
            task.destroy(conn);
        }
    }
}
