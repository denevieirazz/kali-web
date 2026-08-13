using System.Diagnostics;
using System.IO;
using System.Net;
using System.Net.Http;
using System.Security.Cryptography;
using System.Text.Json;
using System.Text.Json.Serialization;
using CloudOS.Host.Security;

namespace CloudOS.Host.Runtime;

public sealed record RuntimeEndpoint(Uri BaseUri, string FrontendDirectory, int ProcessId, string InstanceId, string RunId, string SupervisorToken, string HostLeaseToken);

public sealed class RuntimeExitedEventArgs(int exitCode) : EventArgs
{
    public int ExitCode { get; } = exitCode;
}

public sealed class CloudOsRuntimeSupervisor : IAsyncDisposable
{
    private readonly HttpClient _http = new(new HttpClientHandler
    {
        UseProxy = false,
        Proxy = null,
        AutomaticDecompression = DecompressionMethods.None
    }) { Timeout = TimeSpan.FromSeconds(4) };
    private readonly object _logLock = new();
    private Process? _process;
    private string? _logPath;
    private string? _runtimeDirectory;
    private string? _supervisorToken;
    private RuntimeLeaseServer? _runtimeLease;
    private RuntimeEndpoint? _endpoint;
    private bool _stopping;
    private bool _disposed;

    public event EventHandler<RuntimeExitedEventArgs>? RuntimeExited;

    public async Task<RuntimeEndpoint> StartAsync(HostOptions options, CancellationToken cancellationToken)
    {
        if (_disposed) throw new ObjectDisposedException(nameof(CloudOsRuntimeSupervisor));
        if (_process is not null) throw new InvalidOperationException("O agente CloudOS já foi iniciado.");
        _stopping = false;

        var layout = ResolveLayout(options.ProjectRoot);
        var nodePath = ResolveNodePath(options.NodePath, layout.Root);
        var localRoot = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "CloudOS");
        var runId = Guid.NewGuid().ToString("D");
        _runtimeDirectory = Path.Combine(localRoot, "runtime", runId);
        var dataDirectory = Path.Combine(localRoot, "data");
        var logDirectory = Path.Combine(localRoot, "logs");
        Directory.CreateDirectory(_runtimeDirectory);
        Directory.CreateDirectory(dataDirectory);
        Directory.CreateDirectory(logDirectory);
        _logPath = Path.Combine(logDirectory, $"host-{DateTime.UtcNow:yyyyMMdd}.log");
        _supervisorToken = Convert.ToBase64String(RandomNumberGenerator.GetBytes(48));
        var runtimeLease = RuntimeLeaseServer.Create();
        _runtimeLease = runtimeLease;

        var startInfo = new ProcessStartInfo
        {
            FileName = nodePath,
            WorkingDirectory = layout.Root,
            UseShellExecute = false,
            CreateNoWindow = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true
        };
        var inheritedJwtSecret = startInfo.Environment.TryGetValue("JWT_SECRET", out var jwtSecret) ? jwtSecret : null;
        foreach (var key in startInfo.Environment.Keys.ToArray())
        {
            if (System.Text.RegularExpressions.Regex.IsMatch(
                key,
                "(?:SECRET|TOKEN|PASSWORD|CREDENTIAL|PRIVATE_KEY|API_KEY)",
                System.Text.RegularExpressions.RegexOptions.IgnoreCase | System.Text.RegularExpressions.RegexOptions.CultureInvariant))
                startInfo.Environment.Remove(key);
        }
        if (!string.IsNullOrWhiteSpace(inheritedJwtSecret)) startInfo.Environment["JWT_SECRET"] = inheritedJwtSecret;
        startInfo.ArgumentList.Add(layout.BackendScript);
        startInfo.Environment["NODE_ENV"] = "production";
        startInfo.Environment["PORT"] = "0";
        startInfo.Environment["HOST"] = "127.0.0.1";
        startInfo.Environment["CLOUDOS_NATIVE_HOST"] = "1";
        startInfo.Environment["CLOUDOS_RUN_ID"] = runId;
        startInfo.Environment["CLOUDOS_PARENT_PID"] = Environment.ProcessId.ToString();
        startInfo.Environment["CLOUDOS_RUNTIME_DIR"] = _runtimeDirectory;
        startInfo.Environment["CLOUDOS_DATA_DIR"] = dataDirectory;
        startInfo.Environment["CLOUDOS_FRONTEND_DIST"] = layout.FrontendDist;
        startInfo.Environment["CLOUDOS_TRUSTED_ORIGIN"] = CloudOsOrigins.ShellOrigin;
        startInfo.Environment["CLOUDOS_SUPERVISOR_TOKEN"] = _supervisorToken;
        startInfo.Environment[RuntimeLeaseServer.PipeEnvironmentVariable] = runtimeLease.PipeName;
        startInfo.Environment[RuntimeLeaseServer.TokenEnvironmentVariable] = runtimeLease.Token;

        _process = new Process { StartInfo = startInfo, EnableRaisingEvents = true };
        _process.OutputDataReceived += (_, eventArgs) => AppendLog("agent", eventArgs.Data);
        _process.ErrorDataReceived += (_, eventArgs) => AppendLog("agent:error", eventArgs.Data);
        _process.Exited += (_, _) =>
        {
            ReleaseRuntimeLease();
            if (!_stopping)
                RuntimeExited?.Invoke(this, new RuntimeExitedEventArgs(SafeExitCode(_process)));
        };

        var processStarted = false;
        try
        {
            if (!_process.Start()) throw new InvalidOperationException("O processo do agente CloudOS não pôde ser iniciado.");
            processStarted = true;
            _process.BeginOutputReadLine();
            _process.BeginErrorReadLine();
            AppendLog("host", $"Agente iniciado. pid={_process.Id} run={runId}");

            await runtimeLease.AcceptAuthenticatedClientAsync(_process, runId, cancellationToken);
            AppendLog("host", $"Lease privada autenticada para pid={_process.Id}");
            var manifest = await WaitForManifestAsync(_process, runId, cancellationToken);
            _endpoint = await ValidateHealthAsync(manifest, _process, runId, layout.FrontendDist, cancellationToken);
            AppendLog("host", $"Agente validado em {_endpoint.BaseUri}");
            return _endpoint;
        }
        catch
        {
            if (processStarted)
            {
                await StopAsync(CancellationToken.None);
            }
            else
            {
                _process.Dispose();
                _process = null;
                ReleaseRuntimeLease();
            }
            throw;
        }
    }

    public async Task StopAsync(CancellationToken cancellationToken)
    {
        var process = _process;
        if (process is null) return;
        _stopping = true;

        if (!process.HasExited && _endpoint is not null && _supervisorToken is not null)
        {
            try
            {
                using var request = new HttpRequestMessage(HttpMethod.Post, new Uri(_endpoint.BaseUri, "/_cloudos/supervisor/shutdown"));
                request.Headers.Add("X-CloudOS-Supervisor-Token", _supervisorToken);
                using var response = await _http.SendAsync(request, cancellationToken);
            }
            catch (Exception error) when (error is HttpRequestException or TaskCanceledException)
            {
                AppendLog("host", "O encerramento gracioso do agente não respondeu.");
            }
        }

        if (!process.HasExited)
        {
            try
            {
                using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
                timeout.CancelAfter(TimeSpan.FromSeconds(8));
                await process.WaitForExitAsync(timeout.Token);
            }
            catch (OperationCanceledException)
            {
                // Mata somente o objeto Process iniciado por este supervisor, nunca um PID de arquivo runtime.
                if (!process.HasExited) process.Kill(entireProcessTree: false);
            }
        }

        if (!process.HasExited) await process.WaitForExitAsync(CancellationToken.None);
        AppendLog("host", $"Agente encerrado. exit={SafeExitCode(process)}");
        process.Dispose();
        _process = null;
        _endpoint = null;
        _supervisorToken = null;
        ReleaseRuntimeLease();

        if (_runtimeDirectory is not null)
        {
            try { Directory.Delete(_runtimeDirectory, recursive: true); } catch (IOException) { }
        }
    }

    private async Task<RuntimeManifest> WaitForManifestAsync(Process process, string runId, CancellationToken cancellationToken)
    {
        var path = Path.Combine(_runtimeDirectory!, "backend-port.json");
        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        timeout.CancelAfter(TimeSpan.FromSeconds(30));

        while (true)
        {
            timeout.Token.ThrowIfCancellationRequested();
            if (process.HasExited)
                throw new InvalidOperationException($"O agente encerrou antes de ficar pronto (código {SafeExitCode(process)}).");

            try
            {
                if (File.Exists(path))
                {
                    await using var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);
                    var manifest = await JsonSerializer.DeserializeAsync<RuntimeManifest>(stream, cancellationToken: timeout.Token);
                    if (manifest is not null)
                    {
                        ValidateManifest(manifest, process, runId);
                        return manifest;
                    }
                }
            }
            catch (JsonException)
            {
                // A escrita atômica deve evitar isto; tolera uma leitura transitória sem confiar no arquivo.
            }
            catch (IOException)
            {
                // O processo pode estar concluindo o rename atômico.
            }
            await Task.Delay(120, timeout.Token);
        }
    }

    private static void ValidateManifest(RuntimeManifest manifest, Process process, string runId)
    {
        if (manifest.Host != "127.0.0.1" || manifest.BackendPort is < 1 or > 65535)
            throw new InvalidOperationException("O agente anunciou um endpoint inválido.");
        if (manifest.Pid != process.Id || manifest.ParentPid != Environment.ProcessId)
            throw new InvalidOperationException("A identidade do processo no runtime não corresponde ao filho iniciado.");
        if (manifest.RunId != runId || !Guid.TryParse(manifest.InstanceId, out _))
            throw new InvalidOperationException("A identidade da sessão do agente é inválida.");
        if (!manifest.NativeHost)
            throw new InvalidOperationException("O agente não confirmou o modo de host nativo.");
        if (manifest.LeaseProtocol != RuntimeLeaseServer.ProtocolVersion)
            throw new InvalidOperationException("O agente não confirmou a lease autenticada do host.");
    }

    private async Task<RuntimeEndpoint> ValidateHealthAsync(
        RuntimeManifest manifest,
        Process process,
        string runId,
        string frontendDirectory,
        CancellationToken cancellationToken)
    {
        var origin = new Uri($"http://127.0.0.1:{manifest.BackendPort}/");
        using var request = new HttpRequestMessage(HttpMethod.Get, new Uri(origin, "/_cloudos/supervisor/health"));
        request.Headers.Add("X-CloudOS-Supervisor-Token", _supervisorToken);
        using var response = await _http.SendAsync(request, cancellationToken);
        response.EnsureSuccessStatusCode();
        await using var body = await response.Content.ReadAsStreamAsync(cancellationToken);
        var health = await JsonSerializer.DeserializeAsync<SupervisorHealth>(body, cancellationToken: cancellationToken)
            ?? throw new InvalidOperationException("Health check vazio.");

        if (health.Protocol != 1 || health.Status != "ready" || health.Component != "backend" ||
            health.RunId != runId || health.InstanceId != manifest.InstanceId ||
            health.Pid != process.Id || health.Host != "127.0.0.1" || health.Port != manifest.BackendPort ||
            health.LeaseProtocol != RuntimeLeaseServer.ProtocolVersion)
            throw new InvalidOperationException("O health check não corresponde ao processo CloudOS iniciado.");

        return new RuntimeEndpoint(origin, frontendDirectory, process.Id, health.InstanceId!, runId, _supervisorToken ?? string.Empty, _runtimeLease?.Token ?? string.Empty);
    }

    internal void AppendLog(string source, string? line)
    {
        if (string.IsNullOrWhiteSpace(line) || _logPath is null) return;
        var safeLine = line.Length > 8_192 ? line[..8_192] : line;
        lock (_logLock)
        {
            File.AppendAllText(_logPath, $"{DateTimeOffset.Now:O} [{source}] {safeLine}{Environment.NewLine}");
        }
    }

    private static int SafeExitCode(Process? process)
    {
        try { return process?.HasExited == true ? process.ExitCode : -1; }
        catch { return -1; }
    }

    private void ReleaseRuntimeLease()
    {
        Interlocked.Exchange(ref _runtimeLease, null)?.Dispose();
    }

    private static CloudOsLayout ResolveLayout(string? requestedRoot)
    {
        var candidates = new List<string>();
        if (!string.IsNullOrWhiteSpace(requestedRoot)) candidates.Add(requestedRoot);
        var environmentRoot = Environment.GetEnvironmentVariable("CLOUDOS_PROJECT_ROOT");
        if (!string.IsNullOrWhiteSpace(environmentRoot)) candidates.Add(environmentRoot);
        candidates.Add(AppContext.BaseDirectory);
        candidates.Add(Environment.CurrentDirectory);

        foreach (var candidate in candidates)
        {
            var directory = new DirectoryInfo(Path.GetFullPath(candidate));
            for (var depth = 0; directory is not null && depth < 10; depth++, directory = directory.Parent)
            {
                var sourceBackend = Path.Combine(directory.FullName, "backend", "src", "server.js");
                var sourceWeb = Path.Combine(directory.FullName, "frontend", "dist");
                if (File.Exists(sourceBackend) && File.Exists(Path.Combine(sourceWeb, "index.html")))
                    return new CloudOsLayout(directory.FullName, sourceBackend, sourceWeb);

                var packagedBackend = Path.Combine(directory.FullName, "agent", "backend", "src", "server.js");
                var packagedWeb = Path.Combine(directory.FullName, "web");
                if (File.Exists(packagedBackend) && File.Exists(Path.Combine(packagedWeb, "index.html")))
                    return new CloudOsLayout(directory.FullName, packagedBackend, packagedWeb);
            }
        }
        throw new DirectoryNotFoundException("Não encontrei backend/src/server.js e frontend/dist. Compile o frontend ou informe --root.");
    }

    private static string ResolveNodePath(string? requestedPath, string root)
    {
        var candidates = new[]
        {
            requestedPath,
            Environment.GetEnvironmentVariable("CLOUDOS_NODE_PATH"),
            Path.Combine(root, "runtime", "node.exe"),
            Path.Combine(AppContext.BaseDirectory, "runtime", "node.exe"),
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "hermes", "node", "node.exe")
        };
        foreach (var candidate in candidates)
        {
            if (!string.IsNullOrWhiteSpace(candidate) && File.Exists(candidate)) return Path.GetFullPath(candidate);
        }

        var path = Environment.GetEnvironmentVariable("PATH") ?? string.Empty;
        foreach (var directory in path.Split(Path.PathSeparator, StringSplitOptions.RemoveEmptyEntries))
        {
            var candidate = Path.Combine(directory.Trim('"'), "node.exe");
            if (File.Exists(candidate)) return candidate;
        }
        throw new FileNotFoundException("Node.js não foi encontrado. O pacote final inclui runtime/node.exe; em desenvolvimento use --node <caminho>.");
    }

    public async ValueTask DisposeAsync()
    {
        if (_disposed) return;
        await StopAsync(CancellationToken.None);
        _disposed = true;
        _http.Dispose();
    }

    private sealed record CloudOsLayout(string Root, string BackendScript, string FrontendDist);

    private sealed class RuntimeManifest
    {
        [JsonPropertyName("host")] public string? Host { get; init; }
        [JsonPropertyName("backendPort")] public int BackendPort { get; init; }
        [JsonPropertyName("pid")] public int Pid { get; init; }
        [JsonPropertyName("parentPid")] public int? ParentPid { get; init; }
        [JsonPropertyName("instanceId")] public string? InstanceId { get; init; }
        [JsonPropertyName("runId")] public string? RunId { get; init; }
        [JsonPropertyName("nativeHost")] public bool NativeHost { get; init; }
        [JsonPropertyName("leaseProtocol")] public int LeaseProtocol { get; init; }
    }

    private sealed class SupervisorHealth
    {
        [JsonPropertyName("protocol")] public int Protocol { get; init; }
        [JsonPropertyName("status")] public string? Status { get; init; }
        [JsonPropertyName("component")] public string? Component { get; init; }
        [JsonPropertyName("runId")] public string? RunId { get; init; }
        [JsonPropertyName("instanceId")] public string? InstanceId { get; init; }
        [JsonPropertyName("pid")] public int Pid { get; init; }
        [JsonPropertyName("host")] public string? Host { get; init; }
        [JsonPropertyName("port")] public int Port { get; init; }
        [JsonPropertyName("leaseProtocol")] public int LeaseProtocol { get; init; }
    }
}
