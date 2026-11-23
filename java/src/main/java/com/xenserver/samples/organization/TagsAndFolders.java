package com.xenserver.samples.organization;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.Host;
import com.xensource.xenapi.Session;
import com.xensource.xenapi.VM;

import static com.xenserver.samples.Helpers.vmByName;
import static com.xenserver.samples.PoolConnection.connect;

public final class TagsAndFolders {
    private TagsAndFolders() {
    }

    /**
     * Tag and organize objects.
     *
     * <p>Organize a pool with tags and folders: add tags to a VM and a host (tags work on any object
     * type), place the VM in a folder, read it all back, then tidy up.
     *
     * <p>Run it:
     *
     * <pre>{@code
     * TagsAndFolders.run("https://xenserver", "root", password, "web-01");
     * }</pre>
     */
    public static void run(String url, String user, String password, String vmName) throws Exception {
        Connection conn = connect(url, user, password);
        VM vm = vmByName(conn, vmName);
        Host host = Host.getAll(conn).iterator().next();

        // Tags work on any object type (VM, host, SR, network, …).
        vm.addTags(conn, "web");
        host.addTags(conn, "gold");
        System.out.println("VM tags:   " + vm.getTags(conn));
        System.out.println("Host tags: " + host.getTags(conn));

        // Folder placement lives in other_config["folder"] as a leading-slash path.
        vm.addToOtherConfig(conn, "folder", "/Production/Web");
        System.out.println("VM folder: " + vm.getOtherConfig(conn).get("folder"));

        vm.removeTags(conn, "web");
        host.removeTags(conn, "gold");
        vm.removeFromOtherConfig(conn, "folder");
        System.out.println("OK: tags-and-folders");
        Session.logout(conn);
    }
}
