package com.xenserver.samples.organization;

import com.xensource.xenapi.Connection;
import com.xensource.xenapi.Pool;
import com.xensource.xenapi.Session;
import com.xensource.xenapi.VM;

import org.w3c.dom.Document;
import org.w3c.dom.Element;
import org.w3c.dom.NodeList;

import java.io.StringWriter;
import java.util.Map;

import javax.xml.transform.OutputKeys;
import javax.xml.transform.Transformer;
import javax.xml.transform.TransformerFactory;
import javax.xml.transform.dom.DOMSource;
import javax.xml.transform.stream.StreamResult;

import static com.xenserver.samples.Helpers.parseXml;
import static com.xenserver.samples.Helpers.vmByName;
import static com.xenserver.samples.PoolConnection.connect;

public final class CustomFields {
    private CustomFields() {
    }

    private static final String CUSTOM_FIELD_BASE_KEY = "XenCenter.CustomFields";
    private static final String FIELD_NAME = "Owner";
    private static final String FIELD_KEY = CUSTOM_FIELD_BASE_KEY + "." + FIELD_NAME;

    /**
     * Custom fields.
     *
     * <p>Attach and read a custom name/value field on a VM — arbitrary metadata you define. A
     * management client only shows a field once it has been DEFINED for the pool; the value on the
     * object is a separate step. This sample does both.
     *
     * <p>Run it:
     *
     * <pre>{@code
     * CustomFields.run("https://xenserver", "root", password, "web-01");
     * }</pre>
     */
    public static void run(String url, String user, String password, String vmName) throws Exception {
        Connection conn = connect(url, user, password);
        try {
            VM vm = vmByName(conn, vmName);
            Pool pool = Pool.getAll(conn).iterator().next();

            // The pool's custom field DEFINITIONS (name and type, String or Date) live in a small XML
            // document in pool.gui_config["XenCenter.CustomFields"] (the key keeps its historical
            // name); a client shows no field without one, no matter what value an object carries under
            // XenCenter.CustomFields.<name>.
            Map<String, String> guiConfig = pool.getGuiConfig(conn);
            String previousXml = guiConfig.get(CUSTOM_FIELD_BASE_KEY);
            Document doc = parseXml(previousXml != null ? previousXml : "<CustomFieldDefinitions/>");
            Element root = doc.getDocumentElement();
            boolean addedDefinition = true;
            NodeList existing = root.getElementsByTagName("CustomFieldDefinition");
            for (int i = 0; i < existing.getLength(); i++) {
                if (FIELD_NAME.equals(((Element) existing.item(i)).getAttribute("name"))) {
                    addedDefinition = false;
                    break;
                }
            }
            if (addedDefinition) {
                Element definition = doc.createElement("CustomFieldDefinition");
                definition.setAttribute("name", FIELD_NAME);
                definition.setAttribute("type", "String");
                root.appendChild(definition);
                pool.addToGuiConfig(conn, CUSTOM_FIELD_BASE_KEY, toXmlString(doc));
            }
            System.out.println("Field defined: " + addedDefinition);

            // With the field defined, giving it a value on an object is a plain other_config write.
            vm.addToOtherConfig(conn, FIELD_KEY, "Platform Team");
            System.out.println("Custom field Owner = " + vm.getOtherConfig(conn).get(FIELD_KEY));

            vm.removeFromOtherConfig(conn, FIELD_KEY);
            if (addedDefinition) {
                // Only this sample's own definition is ours to remove, and only by putting back the
                // pool's previous gui_config value exactly (there may be other definitions alongside
                // it).
                if (previousXml != null) {
                    pool.addToGuiConfig(conn, CUSTOM_FIELD_BASE_KEY, previousXml);
                } else {
                    pool.removeFromGuiConfig(conn, CUSTOM_FIELD_BASE_KEY);
                }
            }
            System.out.println("OK: custom-fields");
        } finally {
            Session.logout(conn);
        }
    }

    private static String toXmlString(Document doc) throws Exception {
        Transformer transformer = TransformerFactory.newInstance().newTransformer();
        transformer.setOutputProperty(OutputKeys.OMIT_XML_DECLARATION, "yes");
        StringWriter writer = new StringWriter();
        transformer.transform(new DOMSource(doc), new StreamResult(writer));
        return writer.toString();
    }
}
