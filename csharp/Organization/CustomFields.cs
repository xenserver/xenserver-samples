using System.Collections.Generic;
using System.Linq;
using System.Xml.Linq;
using XenAPI;
using Console = System.Console; // XenAPI also defines a Console class

namespace XenServerWorkflows;

internal static partial class Workflows
{
    private const string CustomFieldBaseKey = "XenCenter.CustomFields";
    private const string FieldName = "Owner";
    private const string FieldKey = CustomFieldBaseKey + "." + FieldName;

    /// <summary>
    /// Attach and read a custom name/value field on a VM — arbitrary metadata you define. A management
    /// client only shows a field once it has been DEFINED for the pool; the value on the object is a
    /// separate step. This sample does both.
    /// </summary>
    /// <example>
    /// <code>
    /// Workflows.CustomFields("https://xenserver", "root", password, "web-01");
    /// </code>
    /// </example>
    public static void CustomFields(string url, string user, string password, string vmName)
    {
        var session = Connect(url, user, password);
        var vm = VmByName(session, vmName);
        var pool = Pool.get_all(session).First().opaque_ref;

        // The pool's custom field DEFINITIONS (name and type, String or Date) live in a small XML document in
        // pool.gui_config["XenCenter.CustomFields"] (the key keeps its historical name); a client shows no
        // field without one, no matter what value an object carries under XenCenter.CustomFields.<name>.
        var previousXml = Pool.get_gui_config(session, pool).GetValueOrDefault(CustomFieldBaseKey);
        var doc = previousXml != null
            ? XDocument.Parse(previousXml)
            : new XDocument(new XElement("CustomFieldDefinitions"));
        var addedDefinition = doc.Root.Elements("CustomFieldDefinition")
            .All(e => (string)e.Attribute("name") != FieldName);
        if (addedDefinition)
        {
            doc.Root.Add(new XElement("CustomFieldDefinition",
                new XAttribute("name", FieldName), new XAttribute("type", "String")));
            Pool.add_to_gui_config(session, pool, CustomFieldBaseKey, doc.ToString(SaveOptions.DisableFormatting));
        }
        Console.WriteLine($"Field defined: {addedDefinition}");

        // With the field defined, giving it a value on an object is a plain other_config write.
        VM.add_to_other_config(session, vm, FieldKey, "Platform Team");
        Console.WriteLine($"Custom field Owner = {VM.get_other_config(session, vm)[FieldKey]}");

        VM.remove_from_other_config(session, vm, FieldKey);
        if (addedDefinition)
        {
            // Only this sample's own definition is ours to remove, and only by putting back the
            // pool's previous gui_config value exactly (there may be other definitions alongside it).
            if (previousXml == null)
                Pool.remove_from_gui_config(session, pool, CustomFieldBaseKey);
            else
                Pool.add_to_gui_config(session, pool, CustomFieldBaseKey, previousXml);
        }

        Console.WriteLine("OK: custom-fields");
        session.logout();
    }
}
