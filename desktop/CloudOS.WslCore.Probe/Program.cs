using System.Collections.Concurrent;
using System.Text;
using System.Text.Json;
using CloudOS.WslCore;

var arguments = ParseArgs(args);
if (!arguments.TryGetValue("distro", out var distro) || !arguments.TryGetValue("core", out var corePath))
{
    Console.Error.WriteLine("Usage: --distro <name> --core <linux-path> [--output <directory>]");
    return 2;
}
var outputDirectory = arguments.TryGetValue("output", out var requestedOutput)
    ? Path.GetFullPath(requestedOutput)
    : Path.GetFullPath(Path.Combine("test-results", "wsl-core-secure-terminal"));
Directory.CreateDirectory(outputDirectory);
var validationPath = Path.Combine(outputDirectory, "validation.json");
var outputs = new ConcurrentDictionary<string, StringBuilder>(StringComparer.Ordinal);
var childPids = new ConcurrentBag<int>();
var checks = new List<string>();
int corePid = 0;
string? distroId = null;
bool? cgroupV2 = null;

try
{
    Environment.SetEnvironmentVariable("CLOUDOS_WSL_CORE_FOUNDATION", "1");
    await using var supervisor = new WslCoreSupervisor();
    using var overall = new CancellationTokenSource(TimeSpan.FromSeconds(60));
    var client = await supervisor.StartAsync(new WslCoreSupervisorOptions(distro, corePath, AllowBootstrap: true), overall.Token);
    client.EventReceived += (_, evt) =>
    {
        if (evt.Type != "session.output" || string.IsNullOrWhiteSpace(evt.SessionId) || string.IsNullOrWhiteSpace(evt.Data)) return;
        byte[] bytes;
        try { bytes = Convert.FromBase64String(evt.Data); } catch (FormatException) { return; }
        var builder = outputs.GetOrAdd(evt.SessionId, _ => new StringBuilder());
        lock (builder) builder.Append(Encoding.UTF8.GetString(bytes));
    };

    var health = await client.HealthAsync(overall.Token);
    Require(health.Status == "ready" && health.Protocol == 2 && health.Pid > 0 && health.Protection == "aes-256-gcm-seq", "health");
    corePid = health.Pid;
    distroId = health.Distro?.Id;
    checks.Add("authenticated-health");
    checks.Add("protected-channel-v2");

    var echo = await client.CreateSessionAsync(new WslCoreCreateSession("/bin/echo", ["cloudos-wsl-core-ok", "literal;not-shell"]), overall.Token);
    Require(!string.IsNullOrWhiteSpace(echo.SessionId) && echo.Pid > 0, "echo-create");
    childPids.Add(echo.Pid);
    var echoExit = await client.WaitAsync(echo.SessionId!, 5_000, overall.Token);
    Require(echoExit.State == "exited" && echoExit.ExitCode == 0, "echo-exit");
    var echoOutput = ReadOutput(outputs, echo.SessionId!);
    Require(echoOutput.Contains("cloudos-wsl-core-ok literal;not-shell", StringComparison.Ordinal), "echo-output-boundary");
    checks.Add("generic-allowlist-remains-shell-free");

    var metrics = await client.MetricsAsync(overall.Token);
    Require(metrics.UptimeSeconds > 0 && metrics.Memory?.TotalBytes > 0 && metrics.ProcessCount > 0, "proc-metrics");
    cgroupV2 = metrics.CgroupV2;
    checks.Add("real-proc-metrics");

    var sleeper = await client.CreateSessionAsync(new WslCoreCreateSession("/bin/sleep", ["30"]), overall.Token);
    Require(!string.IsNullOrWhiteSpace(sleeper.SessionId) && sleeper.Pid > 0, "signal-create");
    childPids.Add(sleeper.Pid);
    await client.SignalAsync(sleeper.SessionId!, "terminate", overall.Token);
    var sleeperExit = await client.WaitAsync(sleeper.SessionId!, 5_000, overall.Token);
    Require(sleeperExit.State == "exited", "signal-exit");
    checks.Add("signal-and-exit");

    var terminal = await client.CreateTerminalAsync(rows: 24, cols: 80, cancellationToken: overall.Token);
    Require(!string.IsNullOrWhiteSpace(terminal.SessionId) && terminal.Pid > 0 && terminal.Pty, "terminal-create");
    childPids.Add(terminal.Pid);
    await client.ResizeAsync(terminal.SessionId!, 36, 120, overall.Token);
    await client.InputAsync(terminal.SessionId!, Encoding.UTF8.GetBytes("printf 'cloudos-terminal-core-v2-ok\\n'\n"), overall.Token);
    var sawTerminal = await WaitForOutputAsync(client, outputs, terminal.SessionId!, "cloudos-terminal-core-v2-ok", overall.Token);
    Require(sawTerminal, "terminal-io");
    await client.SignalAsync(terminal.SessionId!, "hangup", overall.Token);
    var terminalExit = await client.WaitAsync(terminal.SessionId!, 5_000, overall.Token);
    Require(terminalExit.State == "exited", "terminal-exit");
    checks.Add("fixed-terminal-input-output-resize-signal-exit");

    var finalHealth = await client.HealthAsync(overall.Token);
    Require(finalHealth.ActiveSessions == 0, "zero-active-sessions");
    checks.Add("zero-active-sessions");
    await supervisor.StopAsync(overall.Token);
    checks.Add("graceful-shutdown");

    await WriteValidationAsync(validationPath, new
    {
        passed = true,
        physicalValidation = true,
        protocol = 2,
        protection = "aes-256-gcm-seq",
        distribution = distro,
        distroId,
        corePid,
        childPids = childPids.OrderBy(value => value).ToArray(),
        cgroupV2,
        checks,
        databaseTouched = false,
        wslMutated = false,
        elevationRequested = false
    });
    Console.WriteLine(validationPath);
    return 0;
}
catch (Exception error)
{
    var code = error is WslCoreProtocolException protocolError ? protocolError.Code : error.GetType().Name;
    await WriteValidationAsync(validationPath, new
    {
        passed = false,
        physicalValidation = true,
        protocol = 2,
        protection = "aes-256-gcm-seq",
        distribution = distro,
        distroId,
        corePid,
        childPids = childPids.OrderBy(value => value).ToArray(),
        checks,
        errorCode = code,
        databaseTouched = false,
        wslMutated = false,
        elevationRequested = false
    });
    Console.Error.WriteLine($"WSL core validation failed: {code}");
    return 1;
}

static async Task<bool> WaitForOutputAsync(WslCoreClient client, ConcurrentDictionary<string, StringBuilder> outputs, string sessionId, string needle, CancellationToken cancellationToken)
{
    for (var attempt = 0; attempt < 40; attempt++)
    {
        if (ReadOutput(outputs, sessionId).Contains(needle, StringComparison.Ordinal)) return true;
        _ = await client.StatusAsync(sessionId, cancellationToken);
        await Task.Delay(50, cancellationToken);
    }
    return ReadOutput(outputs, sessionId).Contains(needle, StringComparison.Ordinal);
}

static string ReadOutput(ConcurrentDictionary<string, StringBuilder> outputs, string sessionId)
{
    if (!outputs.TryGetValue(sessionId, out var builder)) return string.Empty;
    lock (builder) return builder.ToString();
}

static void Require(bool condition, string name)
{
    if (!condition) throw new InvalidOperationException($"CHECK_FAILED:{name}");
}

static async Task WriteValidationAsync(string path, object value)
{
    var json = JsonSerializer.Serialize(value, new JsonSerializerOptions { WriteIndented = true });
    await File.WriteAllTextAsync(path, json + Environment.NewLine);
}

static Dictionary<string, string> ParseArgs(string[] args)
{
    var values = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
    for (var i = 0; i + 1 < args.Length; i += 2)
    {
        if (!args[i].StartsWith("--", StringComparison.Ordinal)) continue;
        values[args[i][2..]] = args[i + 1];
    }
    return values;
}
