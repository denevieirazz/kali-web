using CloudOS.Host.Security;

var tests = new (string Name, Action Run)[]
{
    ("stable shell origin is exact", StableShellOriginIsExact),
    ("navigation policy rejects origin confusion", NavigationPolicyRejectsOriginConfusion),
    ("runtime bootstrap exposes only validated loopback endpoints", RuntimeBootstrapIsBounded),
    ("runtime bootstrap rejects non-loopback endpoints", RuntimeBootstrapRejectsUntrustedBackend)
};

foreach (var test in tests)
{
    test.Run();
    Console.WriteLine($"PASS {test.Name}");
}

static void StableShellOriginIsExact()
{
    Assert(CloudOsOrigins.ShellOrigin == "https://cloudos.local", "The storage origin must not contain an ephemeral port.");
    Assert(CloudOsOrigins.ShellBaseUri.AbsolutePath == "/", "The shell origin must resolve to the mapped index root.");
    Assert(CloudOsOrigins.ShellBaseUri.IsDefaultPort, "The shell origin must use its default port.");
}

static void NavigationPolicyRejectsOriginConfusion()
{
    var trusted = CloudOsOrigins.ShellBaseUri;
    Assert(NavigationPolicy.IsTrustedDocument(new Uri("https://cloudos.local/desktop?x=1#state"), trusted), "Same-origin paths must be accepted.");
    Assert(!NavigationPolicy.IsTrustedDocument(new Uri("http://cloudos.local/"), trusted), "A scheme change must be rejected.");
    Assert(!NavigationPolicy.IsTrustedDocument(new Uri("https://cloudos.local:8080/"), trusted), "A port change must be rejected.");
    Assert(!NavigationPolicy.IsTrustedDocument(new Uri("https://cloudos.local.evil.example/"), trusted), "A suffix-confusion host must be rejected.");
    Assert(!NavigationPolicy.IsTrustedDocument(new Uri("https://cloudos.local./"), trusted), "A trailing-dot host must not alias the shell.");
    Assert(!NavigationPolicy.IsTrustedDocument(new Uri("https://user@cloudos.local/"), trusted), "User information must be rejected.");
    Assert(!NavigationPolicy.IsTrustedSource("not a uri", trusted), "Malformed bridge sources must be rejected.");
}

static void RuntimeBootstrapIsBounded()
{
    var script = RuntimeBootstrapScript.Build(new Uri("http://127.0.0.1:43127/"));
    Assert(script.Contains("http://127.0.0.1:43127", StringComparison.Ordinal), "The API endpoint must be injected.");
    Assert(script.Contains("ws://127.0.0.1:43127", StringComparison.Ordinal), "The WebSocket endpoint must be injected.");
    Assert(script.Contains("__CLOUDOS_RUNTIME__", StringComparison.Ordinal), "The runtime contract must be installed before app scripts.");
    Assert(script.Contains("Content-Security-Policy", StringComparison.Ordinal), "Mapped documents must receive a shell CSP.");
    Assert(script.Contains("location.origin", StringComparison.Ordinal), "Child frames must be protected by an exact-origin guard.");
}

static void RuntimeBootstrapRejectsUntrustedBackend()
{
    AssertThrows(() => RuntimeBootstrapScript.Build(new Uri("http://localhost:43127/")));
    AssertThrows(() => RuntimeBootstrapScript.Build(new Uri("http://127.0.0.2:43127/")));
    AssertThrows(() => RuntimeBootstrapScript.Build(new Uri("https://127.0.0.1:43127/")));
    AssertThrows(() => RuntimeBootstrapScript.Build(new Uri("http://127.0.0.1:43127/api")));
    AssertThrows(() => RuntimeBootstrapScript.Build(new Uri("http://user@127.0.0.1:43127/")));
}

static void AssertThrows(Action action)
{
    try
    {
        action();
    }
    catch (ArgumentException)
    {
        return;
    }
    throw new InvalidOperationException("An untrusted backend origin was accepted.");
}

static void Assert(bool condition, string message)
{
    if (!condition) throw new InvalidOperationException(message);
}
