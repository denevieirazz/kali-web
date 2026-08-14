using CloudOS.Host.Browser;
using CloudOS.Host.Security;

var tests = new (string Name, Action Run)[]
{
    ("stable shell origin is exact", StableShellOriginIsExact),
    ("navigation policy rejects origin confusion", NavigationPolicyRejectsOriginConfusion),
    ("runtime bootstrap exposes only validated loopback endpoints", RuntimeBootstrapIsBounded),
    ("runtime bootstrap rejects non-loopback endpoints", RuntimeBootstrapRejectsUntrustedBackend),
    ("browser policy normalizes addresses search IPv4 IPv6 and IDN", BrowserPolicyNormalizesInput),
    ("browser policy blocks privileged and dangerous schemes", BrowserPolicyBlocksDangerousSchemes),
    ("browser policy blocks CloudOS and backend aliases", BrowserPolicyBlocksCloudOsOrigins),
    ("browser policy rejects control chars and userinfo", BrowserPolicyRejectsAmbiguousInput),
    ("browser storage isolates shell and browser UDF", BrowserStorageIsIsolated),
    ("browser permission policy is fail closed", BrowserPermissionPolicyIsFailClosed),
    ("browser prompt grants only while origin is unchanged", BrowserPromptOriginIsBound),
    ("browser TLS policy never allows invalid certificates", BrowserTlsPolicyIsFailClosed),
    ("browser crash policy limits recovery loops", BrowserCrashPolicyLimitsRecovery),
    ("browser state persists history and favorites", BrowserStatePersists),
    ("browser state strips sensitive URL data", BrowserStateStripsSensitiveUrlData),
    ("browser state normalization enforces limits", BrowserStateEnforcesLimits),
    ("browser state restores optional session safely", BrowserStateRestoresOptionalSession),
    ("browser state recovers from corruption", BrowserStateRecoversFromCorruption),
    ("browser state can recover from atomic backup", BrowserStateRecoversBackup)
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

static BrowserPolicy NewBrowserPolicy() => new(new Uri("https://cloudos.local/"), new Uri("http://127.0.0.1:43127/"));

static void BrowserPolicyNormalizesInput()
{
    var policy = NewBrowserPolicy();
    Assert(policy.ParseAddressInput("example.com").Uri?.AbsoluteUri == "https://example.com/", "Bare domains must use HTTPS.");
    Assert(policy.ParseAddressInput("example.com:8443/path").Uri?.AbsoluteUri == "https://example.com:8443/path", "Domain ports must remain HTTPS.");
    Assert(policy.ParseAddressInput("localhost:8080").Uri?.AbsoluteUri == "http://localhost:8080/", "localhost must use HTTP.");
    Assert(policy.ParseAddressInput("127.0.0.1:9000/test").Uri?.AbsoluteUri == "http://127.0.0.1:9000/test", "IPv4 loopback must use HTTP.");
    Assert(policy.ParseAddressInput("[::1]:9001/test").Uri?.AbsoluteUri == "http://[::1]:9001/test", "IPv6 loopback must use HTTP.");
    Assert(policy.ParseAddressInput("2001:db8::1").Uri?.Scheme == "https", "Non-loopback IPv6 literals must default to HTTPS.");
    var search = policy.ParseAddressInput("cloudos browser test");
    Assert(search.Allowed && search.IsSearch && search.Uri!.Host == "duckduckgo.com", "Plain text must become a DuckDuckGo search.");
    Assert(policy.ParseAddressInput("https://bücher.example/").Uri!.IdnHost == "xn--bcher-kva.example", "IDN hosts must be normalized to ASCII.");
    Assert(policy.DisplayUri(new Uri("https://bücher.example/")) == "https://xn--bcher-kva.example/", "Address display must use unambiguous punycode.");
}

static void BrowserPolicyBlocksDangerousSchemes()
{
    var policy = NewBrowserPolicy();
    foreach (var scheme in new[] { "file", "javascript", "vbscript", "shell", "cmd", "powershell", "ms-settings", "ms-appx", "edge", "chrome", "devtools", "view-source", "ftp", "mailto", "steam" })
        Assert(!policy.ValidateNavigation($"{scheme}:test").Allowed, $"Scheme {scheme} must be blocked.");
    Assert(!policy.ParseAddressInput("data:text/html,hello").Allowed, "data URLs typed into the address bar must be blocked.");
    Assert(policy.ValidateNavigation("data:text/plain,hello").Allowed, "content-created data URLs may stay inside the browser sandbox.");
    Assert(policy.ValidateNavigation("about:blank", allowAboutBlank: true).Allowed, "about:blank must be allowed only internally.");
}

static void BrowserPolicyBlocksCloudOsOrigins()
{
    var policy = NewBrowserPolicy();
    Assert(!policy.ValidateNavigation("https://cloudos.local/index.html").Allowed, "Shell origin must be blocked.");
    Assert(!policy.ValidateNavigation("https://cloudos.local./index.html").Allowed, "Trailing-dot shell alias must be blocked.");
    Assert(!policy.ValidateNavigation("http://127.0.0.1:43127/api/health").Allowed, "Ephemeral backend origin must be blocked.");
    Assert(!policy.ValidateNavigation("http://localhost:43127/api/health").Allowed, "localhost alias of backend must be blocked.");
    Assert(!policy.ValidateNavigation("http://[::1]:43127/api/health").Allowed, "IPv6 loopback alias of backend must be blocked.");
    Assert(policy.ValidateNavigation("http://127.0.0.1:9999/").Allowed, "Unrelated localhost development services must remain accessible.");
}

static void BrowserPolicyRejectsAmbiguousInput()
{
    var policy = NewBrowserPolicy();
    Assert(!policy.ParseAddressInput("https://user:pass@example.com/").Allowed, "userinfo must be rejected.");
    Assert(!policy.ParseAddressInput("https://example.com/\r\nX-Test: 1").Allowed, "CR/LF must be rejected.");
    Assert(!policy.ParseAddressInput("https://example.com/\0").Allowed, "NUL must be rejected.");
    Assert(!policy.ParseAddressInput(new string('a', BrowserPolicy.MaxInputLength + 1)).Allowed, "Oversized input must be rejected.");
}

static void BrowserStorageIsIsolated()
{
    var local = Path.Combine(Path.GetTempPath(), "cloudos-layout-test");
    var browser = BrowserStorageLayout.BrowserUserDataFolder(local);
    var shell = BrowserStorageLayout.ShellUserDataFolder(local);
    Assert(BrowserStorageLayout.AreIsolated(browser, shell), "Browser and shell UDFs must be different.");
    Assert(browser.EndsWith(Path.Combine("CloudOS", "Browser", "WebView2"), StringComparison.OrdinalIgnoreCase), "Browser UDF path is incorrect.");
    Assert(shell.EndsWith(Path.Combine("CloudOS", "WebView2"), StringComparison.OrdinalIgnoreCase), "Shell UDF path is incorrect.");
}

static void BrowserPermissionPolicyIsFailClosed()
{
    foreach (var prompt in new[] { "Camera", "Microphone", "Geolocation", "Notifications", "MultipleAutomaticDownloads" })
        Assert(BrowserSecurityPolicy.Permission(prompt) == BrowserPermissionDisposition.Prompt, $"{prompt} should prompt.");
    foreach (var denied in new[] { "OtherSensors", "ClipboardRead", "UnknownPermission", "MidiSystemExclusiveMessages", "WindowManagement" })
        Assert(BrowserSecurityPolicy.Permission(denied) == BrowserPermissionDisposition.Deny, $"{denied} should be denied.");
    Assert(!BrowserSecurityPolicy.SavesPermissionInProfile, "Permission decisions must never persist in the profile.");
}

static void BrowserPromptOriginIsBound()
{
    Assert(BrowserSecurityPolicy.IsSameOrigin("https://example.com/path", "https://example.com/other"), "Same origin must remain eligible.");
    Assert(!BrowserSecurityPolicy.IsSameOrigin("https://example.com/", "https://evil.example/"), "Host change must deny a pending prompt.");
    Assert(!BrowserSecurityPolicy.IsSameOrigin("https://example.com/", "http://example.com/"), "Scheme change must deny a pending prompt.");
    Assert(!BrowserSecurityPolicy.IsSameOrigin("https://example.com/", "https://example.com:8443/"), "Port change must deny a pending prompt.");
    Assert(!BrowserSecurityPolicy.IsSameOrigin("https://example.com/", null), "Closed navigation must deny a pending prompt.");
}

static void BrowserTlsPolicyIsFailClosed() =>
    Assert(!BrowserSecurityPolicy.AllowsInvalidServerCertificate, "Invalid TLS certificates must never be allowed.");

static void BrowserCrashPolicyLimitsRecovery()
{
    var now = DateTimeOffset.UtcNow;
    Assert(BrowserCrashPolicy.ShouldRecover(null, now), "First renderer crash should be recoverable.");
    Assert(!BrowserCrashPolicy.ShouldRecover(now.AddSeconds(-10), now), "Second crash within 30 seconds must stop recovery.");
    Assert(BrowserCrashPolicy.ShouldRecover(now.AddSeconds(-31), now), "A later crash may be recovered once.");
}

static void BrowserStatePersists()
{
    using var temp = new TempDirectory();
    var path = Path.Combine(temp.Path, "browser-state.v1.json");
    var store = new BrowserStateStore(path);
    var uri = new Uri("https://example.com/");
    store.AddHistory(uri, "Example");
    Assert(store.ToggleFavorite(uri, "Example"), "First toggle must add favorite.");
    var reloaded = new BrowserStateStore(path);
    Assert(reloaded.History.Count == 1 && reloaded.History[0].Url == uri.AbsoluteUri, "History must survive reload.");
    Assert(reloaded.Favorites.Count == 1 && reloaded.IsFavorite(uri), "Favorite must survive reload.");
    Assert(!reloaded.ToggleFavorite(uri, "Example"), "Second toggle must remove favorite.");
}

static void BrowserStateStripsSensitiveUrlData()
{
    using var temp = new TempDirectory();
    var path = Path.Combine(temp.Path, "browser-state.v1.json");
    var store = new BrowserStateStore(path);
    var uri = new Uri("https://example.com/path?ok=1&access_token=SECRET&code=RECOVERY#private");
    store.AddHistory(uri, "Sensitive");
    store.ToggleFavorite(uri, "Sensitive");
    var serialized = File.ReadAllText(path);
    Assert(serialized.Contains("ok=1", StringComparison.Ordinal), "Non-sensitive query values should survive.");
    Assert(!serialized.Contains("SECRET", StringComparison.Ordinal), "Access tokens must not be persisted.");
    Assert(!serialized.Contains("RECOVERY", StringComparison.Ordinal), "Recovery-like codes must not be persisted.");
    Assert(!serialized.Contains("#private", StringComparison.Ordinal), "Fragments must not be persisted.");
}

static void BrowserStateEnforcesLimits()
{
    var history = Enumerable.Range(0, BrowserStateStore.HistoryLimit + 25)
        .Select(i => new BrowserHistoryEntry($"https://example.com/{i}", $"Entry {i}", DateTimeOffset.UtcNow.AddSeconds(i))).ToList();
    var favorites = Enumerable.Range(0, BrowserStateStore.FavoritesLimit + 5)
        .Select(i => new BrowserFavorite(Guid.NewGuid().ToString("D"), $"https://favorite{i}.example/", $"Favorite {i}", DateTimeOffset.UtcNow.AddSeconds(i))).ToList();
    var normalized = BrowserStateStore.Normalize(new BrowserStateDocument(1, history, favorites));
    Assert(normalized.History!.Count == BrowserStateStore.HistoryLimit && normalized.History[0].Url.EndsWith("/25", StringComparison.Ordinal), "History must trim oldest entries.");
    Assert(normalized.Favorites!.Count == BrowserStateStore.FavoritesLimit && normalized.Favorites[0].Url.Contains("favorite5.example", StringComparison.Ordinal), "Favorites must trim oldest entries.");
}

static void BrowserStateRestoresOptionalSession()
{
    using var temp = new TempDirectory();
    var path = Path.Combine(temp.Path, "browser-state.v1.json");
    var store = new BrowserStateStore(path);
    store.SetRestoreLastSession(true);
    store.SaveSession(new[]
    {
        new BrowserSessionTab("https://one.example/?token=SECRET&safe=1", true),
        new BrowserSessionTab("file:///C:/Windows/win.ini", false),
        new BrowserSessionTab("https://two.example/", false)
    }, 2);
    var reloaded = new BrowserStateStore(path);
    Assert(reloaded.RestoreLastSession, "Restore-session preference must persist.");
    var session = reloaded.Session;
    if (session is null) throw new InvalidOperationException("A valid saved session must be restored.");
    var tabs = session.Tabs;
    if (tabs is null) throw new InvalidOperationException("Restored session tabs must be normalized to a non-null collection.");
    Assert(tabs.Count == 2, "Unsafe session URLs must be discarded.");
    Assert(tabs[0].Pinned, "Pinned state must survive session persistence.");
    Assert(!tabs[0].Url.Contains("SECRET", StringComparison.Ordinal), "Session persistence must strip token-like values.");
    Assert(session.ActiveIndex == 1, "Active index must be clamped after unsafe tabs are removed.");
}

static void BrowserStateRecoversFromCorruption()
{
    using var temp = new TempDirectory();
    var path = Path.Combine(temp.Path, "browser-state.v1.json");
    File.WriteAllText(path, "{not-json");
    var store = new BrowserStateStore(path);
    Assert(store.History.Count == 0 && store.Favorites.Count == 0, "Corrupt state without backup must fail closed.");
    Assert(Directory.GetFiles(temp.Path, "browser-state.v1.json.corrupt-*").Length == 1, "Corrupt state must be quarantined.");
}

static void BrowserStateRecoversBackup()
{
    using var temp = new TempDirectory();
    var path = Path.Combine(temp.Path, "browser-state.v1.json");
    var store = new BrowserStateStore(path);
    store.AddHistory(new Uri("https://first.example/"), "First");
    store.AddHistory(new Uri("https://second.example/"), "Second");
    Assert(File.Exists(path + ".bak"), "Atomic backup must exist after state replacement.");
    File.WriteAllText(path, "{corrupt");
    var recovered = new BrowserStateStore(path);
    Assert(recovered.History.Count >= 1, "A valid atomic backup must recover state after corruption.");
}

static void AssertThrows(Action action)
{
    try { action(); }
    catch (ArgumentException) { return; }
    throw new InvalidOperationException("An untrusted backend origin was accepted.");
}

static void Assert(bool condition, string message)
{
    if (!condition) throw new InvalidOperationException(message);
}

sealed class TempDirectory : IDisposable
{
    public string Path { get; } = System.IO.Path.Combine(System.IO.Path.GetTempPath(), "cloudos-host-tests", Guid.NewGuid().ToString("N"));

    public TempDirectory() => Directory.CreateDirectory(Path);

    public void Dispose()
    {
        try { Directory.Delete(Path, recursive: true); }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        {
            Console.Error.WriteLine($"WARN temp cleanup failed: {error.GetType().Name}");
        }
    }
}
