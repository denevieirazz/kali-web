using System.Diagnostics;
using System.Net.Http;
using System.Security.Cryptography;
using System.Text.Json;

namespace CloudOS.Bootstrap;

public sealed class WebOnlySession : IAsyncDisposable
{
    private readonly HttpClient _http = new(new HttpClientHandler { UseProxy = false, Proxy = null }) { Timeout = TimeSpan.FromSeconds(3) };
    private Process? _process;
    private string? _runtimeDirectory;
    private string? _token;
    public Uri? Url { get; private set; }

    public async Task<Uri> StartAsync(BootstrapOptions options, CancellationToken cancellationToken)
    {
        var root = DistributionEnvironment.ResolvePackageRoot(options);
        var node = PrerequisiteProbe.ResolveNode(options, root) ?? throw new FileNotFoundException("Runtime Node empacotado não encontrado.");
        var backend = PrerequisiteProbe.ResolveBackend(root) ?? throw new FileNotFoundException("Backend de produção não encontrado.");
        var frontend = PrerequisiteProbe.ResolveFrontend(root) ?? throw new DirectoryNotFoundException("Frontend de produção não encontrado.");
        var localRoot = DistributionEnvironment.ResolveLocalRoot();
        _runtimeDirectory = Path.Combine(localRoot, "runtime", $"webonly-{Guid.NewGuid():N}");
        var data = Path.Combine(localRoot, "data");
        var logs = Path.Combine(localRoot, "logs");
        Directory.CreateDirectory(_runtimeDirectory);
        Directory.CreateDirectory(data);
        Directory.CreateDirectory(logs);
        _token = Convert.ToBase64String(RandomNumberGenerator.GetBytes(48));

        var start = new ProcessStartInfo { FileName = node, WorkingDirectory = root, UseShellExecute = false, CreateNoWindow = true, RedirectStandardOutput = true, RedirectStandardError = true };
        start.ArgumentList.Add(backend);
        start.Environment["NODE_ENV"] = "production";
        start.Environment["PORT"] = "0";
        start.Environment["HOST"] = "127.0.0.1";
        start.Environment["CLOUDOS_RUNTIME_DIR"] = _runtimeDirectory;
        start.Environment["CLOUDOS_DATA_DIR"] = data;
        start.Environment["CLOUDOS_FRONTEND_DIST"] = frontend;
        start.Environment["CLOUDOS_SUPERVISOR_TOKEN"] = _token;
        foreach (var key in start.Environment.Keys.ToArray())
        {
            if (System.Text.RegularExpressions.Regex.IsMatch(key, "(?:PASSWORD|CREDENTIAL|PRIVATE_KEY|API_KEY)", System.Text.RegularExpressions.RegexOptions.IgnoreCase | System.Text.RegularExpressions.RegexOptions.CultureInvariant))
                start.Environment.Remove(key);
        }

        _process = new Process { StartInfo = start, EnableRaisingEvents = true };
        if (!_process.Start()) throw new InvalidOperationException("Não foi possível iniciar o backend WebOnly.");
        _process.BeginOutputReadLine();
        _process.BeginErrorReadLine();

        var runtimeFile = Path.Combine(_runtimeDirectory, "backend-port.json");
        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        timeout.CancelAfter(TimeSpan.FromSeconds(30));
        while (true)
        {
            timeout.Token.ThrowIfCancellationRequested();
            if (_process.HasExited) throw new InvalidOperationException("O backend WebOnly encerrou antes de ficar pronto.");
            try
            {
                if (File.Exists(runtimeFile))
                {
                    using var document = JsonDocument.Parse(File.ReadAllText(runtimeFile));
                    var rootElement = document.RootElement;
                    if (rootElement.GetProperty("pid").GetInt32() != _process.Id) throw new InvalidOperationException("Manifesto WebOnly pertence a outro processo.");
                    var port = rootElement.GetProperty("backendPort").GetInt32();
                    var url = new Uri($"http://127.0.0.1:{port}/");
                    using var response = await _http.GetAsync(new Uri(url, "api/health"), timeout.Token);
                    if (response.IsSuccessStatusCode) { Url = url; return url; }
                }
            }
            catch (IOException) { }
            catch (JsonException) { }
            await Task.Delay(120, timeout.Token);
        }
    }

    public void OpenBrowser()
    {
        if (Url is null) throw new InvalidOperationException("Sessão WebOnly ainda não está pronta.");
        Process.Start(new ProcessStartInfo(Url.ToString()) { UseShellExecute = true });
    }

    public async Task StopAsync(CancellationToken cancellationToken)
    {
        var process = _process;
        if (process is null) return;
        if (!process.HasExited && Url is not null && _token is not null)
        {
            try
            {
                using var request = new HttpRequestMessage(HttpMethod.Post, new Uri(Url, "_cloudos/supervisor/shutdown"));
                request.Headers.Add("X-CloudOS-Supervisor-Token", _token);
                using var response = await _http.SendAsync(request, cancellationToken);
            }
            catch { }
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
                if (!process.HasExited) process.Kill(entireProcessTree: false);
            }
        }
        if (!process.HasExited) await process.WaitForExitAsync(CancellationToken.None);
        process.Dispose();
        _process = null;
        Url = null;
        _token = null;
        try { if (_runtimeDirectory is not null && Directory.Exists(_runtimeDirectory)) Directory.Delete(_runtimeDirectory, true); } catch (IOException) { }
    }

    public async ValueTask DisposeAsync()
    {
        await StopAsync(CancellationToken.None);
        _http.Dispose();
    }
}
