// Connecting to a pool: accept the host's self-signed certificate, log in, and follow
// HOST_IS_SLAVE to the coordinator when given a pool member.
//
// Accepting the certificate without checking it suits a test pool. In production, check it: give the
// hosts a certificate from a CA you trust, or trust the pool's own certificate explicitly.

using System;
using System.Net.Http;
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
            // is up).
            return Login($"https://{f.ErrorDescription[1]}", user, password);
        }
    }

    internal static Session Login(string url, string user, string password)
    {
        var session = new Session(url);
        TrustHostCertificate(session);
        session.login_with_password(user, password, "1.0", "sdk-examples");
        return session;
    }

    /// <summary>Accept the host's self-signed certificate on a session's API calls.</summary>
    internal static void TrustHostCertificate(Session session) =>
        session.JsonRpcClient.ServerCertificateValidationCallback = (_, _, _, _) => true;

    // --- HTTP transfers ---

    /// <summary>An HTTP client that accepts the host's self-signed certificate, as Connect does.</summary>
    internal static HttpClient InsecureHttpClient() =>
        new(new HttpClientHandler { ServerCertificateCustomValidationCallback = (_, _, _, _) => true })
        {
            Timeout = TimeSpan.FromMinutes(5),
        };
}
