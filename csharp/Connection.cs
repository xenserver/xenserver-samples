// Connecting to a pool: accept the host's self-signed certificate, log in, and follow
// HOST_IS_SLAVE to the coordinator when given a pool member - as XenCenter does.

using XenAPI;

namespace XenServerWorkflows;

internal static partial class Workflows
{
    // --- connect ---
    internal static Session Connect(string url, string user, string password)
    {
        try
        {
            return Login(url, user, password);
        }
        catch (Failure f) when (f.ErrorDescription[0] == "HOST_IS_SLAVE")
        {
            // A pool member names the coordinator's address; reconnect there (assuming the coordinator
            // is up), exactly as XenCenter does when you add a member server.
            return Login($"https://{f.ErrorDescription[1]}", user, password);
        }
    }

    internal static Session Login(string url, string user, string password)
    {
        var session = new Session(url);
        // Accept the host's self-signed certificate.
        session.JsonRpcClient.ServerCertificateValidationCallback = (req, cert, chain, errors) => true;
        session.login_with_password(user, password, "1.0", "sdk-examples");
        return session;
    }
}
