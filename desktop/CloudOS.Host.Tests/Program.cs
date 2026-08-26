using CloudOS.Host.Browser;
using CloudOS.Host.Native;
using CloudOS.Host.Security;
using System.ComponentModel;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text.Json;

if (args is ["--native-contained-fixture-exit"]) return;
if (args is ["--native-contained-fixture-wait"])
{
    Thread.Sleep(TimeSpan.FromSeconds(30));
    return;
}
if (args is ["--native-contained-fixture-window"])
{
    NativeFixtureWindow.RunVisibleMessageLoop();
    return;
}
if (args is ["--native-contained-fixture-spawn-window-child"])
{
    var childStart = new ProcessStartInfo
    {
        FileName = Environment.ProcessPath ?? throw new InvalidOperationException("The test process path is unavailable."),
        UseShellExecute = false
    };
    foreach (var argument in FixtureArguments("--native-contained-fixture-window"))
        childStart.ArgumentList.Add(argument);
    using var child = Process.Start(childStart)
        ?? throw new InvalidOperationException("The contained child fixture could not be started.");
    Thread.Sleep(TimeSpan.FromSeconds(30));
    return;
}

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
    ("browser state can recover from atomic backup", BrowserStateRecoversBackup),
    ("native launch accepts only direct host descriptors", NativeLaunchAcceptsOnlyDirectDescriptors),
    ("native launch rejects broker and UWP kinds", NativeLaunchRejectsBrokersAndUwp),
    ("native launch reports managed only after HWND correlation", NativeLaunchReportsManagedOnlyAfterCorrelation),
    ("native containment failures require termination", NativeContainmentFailuresRequireTermination),
    ("native launch descriptor preserves argv JSON", NativeLaunchDescriptorPreservesArgvJson),
    ("native command line quoting is bounded", NativeCommandLineQuotingIsBounded),
    ("native launcher tracks suspended process before resume", NativeLauncherTracksSuspendedProcessBeforeResume),
    ("cmd script GUI descendant is contained by the same Job", NativeScriptLaunchContract.Validate),
    ("native job child HWND is quarantined and escape is detected", NativeJobChildWindowIsQuarantined)
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

static void NativeLaunchAcceptsOnlyDirectDescriptors()
{
    Assert(NativeLaunchContainmentPolicy.EvaluateLaunchKind("windows-executable").Allowed,
        "A direct executable descriptor must be eligible for host-owned suspended launch.");
    Assert(NativeLaunchContainmentPolicy.EvaluateLaunchKind("windows-shortcut-direct").Allowed,
        "A verified shortcut target descriptor must be eligible for host-owned suspended launch.");
    Assert(NativeLaunchContainmentPolicy.AllowsArgumentVector("windows-shortcut-direct", 0),
        "A direct shortcut target with no raw shortcut arguments may reach the Host boundary.");
    Assert(!NativeLaunchContainmentPolicy.AllowsArgumentVector("windows-shortcut-direct", 1),
        "A shortcut argument string must never be approximated as argv.");
    Assert(NativeLaunchContainmentPolicy.AllowsArgumentVector("windows-executable", 3),
        "A direct executable may carry a validated argv array.");
    Assert(!NativeLaunchContainmentPolicy.EvaluateLaunchKind(null).Allowed, "A missing launch kind must fail closed.");
}

static void NativeLaunchRejectsBrokersAndUwp()
{
    foreach (var kind in new[] { "windows-start-app", "windows-shortcut", "uwp", "protocol", "brokered", "" })
    {
        var decision = NativeLaunchContainmentPolicy.EvaluateLaunchKind(kind);
        Assert(!decision.Allowed && decision.ErrorCode == "APP_LAUNCH_KIND_UNSUPPORTED", $"Launch kind {kind} must be unavailable.");
    }

    foreach (var broker in new[] { "explorer", "RuntimeBroker", "ApplicationFrameHost", "wslhost" })
        Assert(NativeLaunchContainmentPolicy.IsSharedBroker(broker), $"Shared broker {broker} must never be adopted or killed.");
}

static void NativeLaunchReportsManagedOnlyAfterCorrelation()
{
    Assert(!NativeLaunchContainmentPolicy.CanReportManaged(true, false, false), "A tracked PID without an HWND is not managed.");
    Assert(!NativeLaunchContainmentPolicy.CanReportManaged(true, true, true), "A broker HWND is not an exclusive managed capability.");
    Assert(NativeLaunchContainmentPolicy.CanReportManaged(true, true, false), "A direct tracked process with a quarantined HWND may be reported managed.");
}

static void NativeContainmentFailuresRequireTermination()
{
    foreach (var failure in Enum.GetValues<NativeContainmentFailure>())
        Assert(NativeLaunchContainmentPolicy.RequiresTermination(failure), $"Failure {failure} must terminate instead of restoring an external window.");
}

static void NativeLaunchDescriptorPreservesArgvJson()
{
    var processPath = Environment.ProcessPath ?? throw new InvalidOperationException("The test process path is unavailable.");
    var json = JsonSerializer.Serialize(new
    {
        executable = processPath,
        arguments = new[] { "--profile", "path with spaces\\", "quoted\"value", "" },
        workingDirectory = AppContext.BaseDirectory
    });
    var descriptor = JsonSerializer.Deserialize<NativeProcessLaunchDescriptor>(json)
        ?? throw new InvalidOperationException("The native launch descriptor was not deserialized.");
    Assert(descriptor.Arguments is ["--profile", "path with spaces\\", "quoted\"value", ""],
        "The backend-to-host contract must preserve exact argv entries and quoting boundaries.");
    var validated = descriptor.Validate();
    Assert(validated.Arguments.SequenceEqual(descriptor.Arguments!), "Validation must not split or rewrite argv.");

    AssertThrowsJson(() => JsonSerializer.Deserialize<NativeProcessLaunchDescriptor>(
        """{"executable":"C:\\app.exe","arguments":"--unsafe split","workingDirectory":"C:\\"}"""));
    AssertThrowsArgument(() => (JsonSerializer.Deserialize<NativeProcessLaunchDescriptor>(
        """{"executable":"C:\\app.exe","workingDirectory":"C:\\"}""")
        ?? throw new InvalidOperationException()).Validate());
}

static void NativeCommandLineQuotingIsBounded()
{
    Assert(NativeContainedProcessLauncher.QuoteArgument("") == "\"\"", "Empty argv entries must be preserved.");
    Assert(NativeContainedProcessLauncher.QuoteArgument("plain") == "plain", "Plain arguments must not be rewritten.");
    Assert(NativeContainedProcessLauncher.QuoteArgument("a b\\") == "\"a b\\\\\"", "Trailing backslashes in quoted arguments must be doubled.");
    Assert(NativeContainedProcessLauncher.QuoteArgument("a\"b") == "\"a\\\"b\"", "Embedded quotes must be escaped using CommandLineToArgvW rules.");

    var processPath = Environment.ProcessPath ?? throw new InvalidOperationException("The test process path is unavailable.");
    var spec = NativeProcessLaunchSpec.Create(processPath, FixtureArguments("--native-contained-fixture-exit"), AppContext.BaseDirectory);
    Assert(Path.IsPathFullyQualified(spec.Executable) && spec.Executable.EndsWith(".exe", StringComparison.OrdinalIgnoreCase), "Launch specs must resolve an existing local .exe.");
    AssertThrowsArgument(() => NativeProcessLaunchSpec.Create("relative.exe", [], null));
    var explorer = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows), "explorer.exe");
    AssertThrowsArgument(() => NativeProcessLaunchSpec.Create(explorer, [], null));
}

static void NativeLauncherTracksSuspendedProcessBeforeResume()
{
    var processPath = Environment.ProcessPath ?? throw new InvalidOperationException("The test process path is unavailable.");
    var spec = NativeProcessLaunchSpec.Create(processPath, FixtureArguments("--native-contained-fixture-wait"), AppContext.BaseDirectory);
    using var lease = NativeContainedProcessLauncher.StartSuspended(spec);
    using var windows = new NativeWindowManager();
    Assert(!lease.IsResumed && !lease.Process.HasExited, "The fixture must be alive and suspended before tracking.");
    windows.TrackLaunchedProcess(lease.Process);
    Assert(windows.IsTrackedProcess(lease.ProcessId), "The exact suspended process must be tracked before ResumeThread.");
    lease.Resume();
    Assert(lease.IsResumed, "The tracked primary thread must resume exactly once.");
    Assert(lease.TryTerminate(3_000, out var error), error ?? "The kill-on-close Job did not terminate the fixture.");
    Assert(windows.TryTerminateTrackedProcess(lease.ProcessId, out error), error ?? "The exited fixture capability was not revoked.");
}

static void NativeJobChildWindowIsQuarantined()
{
    var processPath = Environment.ProcessPath ?? throw new InvalidOperationException("The test process path is unavailable.");
    var spec = NativeProcessLaunchSpec.Create(
        processPath,
        FixtureArguments("--native-contained-fixture-spawn-window-child"),
        AppContext.BaseDirectory);
    using var lease = NativeContainedProcessLauncher.StartSuspended(spec);
    using var windows = new NativeWindowManager();
    windows.TrackLaunchedProcess(lease.Process);
    lease.Resume();

    NativeWindowSnapshot? childWindow = null;
    IReadOnlyList<int> members = [];
    var deadline = DateTimeOffset.UtcNow.AddSeconds(8);
    while (DateTimeOffset.UtcNow < deadline && childWindow is null)
    {
        members = NativeContainedJobTracker.Synchronize(lease, windows);
        windows.Refresh();
        childWindow = windows.GetWindows()
            .FirstOrDefault(window => window.ProcessId != lease.ProcessId
                && window.Title == NativeFixtureWindow.Title);
        if (childWindow is null) Thread.Sleep(25);
    }

    Assert(members.Count >= 2, "The root wrapper and its child must both remain inside the Job.");
    Assert(childWindow is not null, "The child-created HWND must be correlated through Job membership.");
    var quarantinedWindow = childWindow
        ?? throw new InvalidOperationException("The child-created HWND was not observed.");
    Assert(!quarantinedWindow.IsVisible && windows.IsTrackedProcess(quarantinedWindow.ProcessId),
        "A child HWND must be hidden and tracked before it becomes a public session.");

    var owner = NativeFixtureWindow.CreateHiddenOwner();
    try
    {
        var bounds = new NativeWindowBounds(100, 100, 360, 240);
        Assert(windows.TryAttach(quarantinedWindow.Handle, owner.ToInt64(), bounds, true, out var attachError),
            attachError ?? "The fixture HWND could not be attached.");

        var hwnd = new IntPtr(quarantinedWindow.Handle);
        NativeMethods.SetWindowStyle(
            hwnd,
            NativeMethods.GetWindowStyle(hwnd) | NativeMethods.WS_CAPTION);
        windows.Refresh();

        Assert(windows.TryGetContainmentFailure(quarantinedWindow.ProcessId, out var failure)
            && failure.Contains("frame", StringComparison.Ordinal),
            "Restoring an external window frame must be recorded as terminal containment loss.");
        Assert(!NativeMethods.IsWindowVisible(hwnd), "A containment escape must be hidden before Job termination.");
    }
    finally
    {
        NativeFixtureWindow.Destroy(owner);
    }

    Assert(lease.TryTerminate(3_000, out var terminationError),
        terminationError ?? "The Job did not terminate the wrapper and child fixture.");
    foreach (var processId in members)
        Assert(windows.TryTerminateTrackedProcess(processId, out terminationError),
            terminationError ?? "A child process capability was not revoked after Job termination.");
}

static string[] FixtureArguments(string fixtureArgument)
{
    var processPath = Environment.ProcessPath ?? throw new InvalidOperationException("The test process path is unavailable.");
    return string.Equals(Path.GetFileNameWithoutExtension(processPath), "dotnet", StringComparison.OrdinalIgnoreCase)
        ? [System.Reflection.Assembly.GetExecutingAssembly().Location, fixtureArgument]
        : [fixtureArgument];
}

static void AssertThrowsArgument(Action action)
{
    try { action(); }
    catch (ArgumentException) { return; }
    throw new InvalidOperationException("An invalid native launch descriptor was accepted.");
}

static void AssertThrowsJson(Action action)
{
    try { action(); }
    catch (JsonException) { return; }
    throw new InvalidOperationException("A raw command-line string was accepted as argv JSON.");
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

static class NativeFixtureWindow
{
    internal const string Title = "CloudOS Native Containment Fixture";
    private const uint WsOverlappedWindow = 0x00CF0000;
    private const uint WsPopup = 0x80000000;
    private const uint WsVisible = 0x10000000;
    private const uint WsExAppWindow = 0x00040000;

    internal static void RunVisibleMessageLoop()
    {
        var hwnd = CreateWindowEx(
            WsExAppWindow,
            "STATIC",
            Title,
            WsPopup | WsVisible,
            20,
            20,
            420,
            280,
            IntPtr.Zero,
            IntPtr.Zero,
            GetModuleHandle(null),
            IntPtr.Zero);
        if (hwnd == IntPtr.Zero)
            throw new Win32Exception(Marshal.GetLastWin32Error(), "The native fixture HWND could not be created.");
        ShowWindow(hwnd, 5);
        UpdateWindow(hwnd);
        while (GetMessage(out var message, IntPtr.Zero, 0, 0) > 0)
        {
            TranslateMessage(ref message);
            DispatchMessage(ref message);
        }
    }

    internal static IntPtr CreateHiddenOwner()
    {
        var hwnd = CreateWindowEx(
            0,
            "STATIC",
            "CloudOS Test Owner",
            WsOverlappedWindow,
            0,
            0,
            640,
            480,
            IntPtr.Zero,
            IntPtr.Zero,
            GetModuleHandle(null),
            IntPtr.Zero);
        if (hwnd == IntPtr.Zero)
            throw new Win32Exception(Marshal.GetLastWin32Error(), "The test owner HWND could not be created.");
        return hwnd;
    }

    internal static void Destroy(IntPtr hwnd)
    {
        if (hwnd != IntPtr.Zero) DestroyWindow(hwnd);
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct Point
    {
        internal int X;
        internal int Y;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct Message
    {
        internal IntPtr Hwnd;
        internal uint Value;
        internal UIntPtr WParam;
        internal IntPtr LParam;
        internal uint Time;
        internal Point Location;
        internal uint Private;
    }

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
    private static extern IntPtr GetModuleHandle(string? moduleName);

    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern IntPtr CreateWindowEx(
        uint extendedStyle,
        string className,
        string windowName,
        uint style,
        int x,
        int y,
        int width,
        int height,
        IntPtr parent,
        IntPtr menu,
        IntPtr instance,
        IntPtr parameter);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool ShowWindow(IntPtr hwnd, int command);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool UpdateWindow(IntPtr hwnd);

    [DllImport("user32.dll")]
    private static extern int GetMessage(out Message message, IntPtr hwnd, uint min, uint max);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool TranslateMessage(ref Message message);

    [DllImport("user32.dll")]
    private static extern IntPtr DispatchMessage(ref Message message);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool DestroyWindow(IntPtr hwnd);
}
