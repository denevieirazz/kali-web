using System.Diagnostics;
using System.Net.Sockets;
using System.Security.Cryptography;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace CloudOS.WslCore;

public sealed class WslCoreSupervisor : IAsyncDisposable
{
    private static readonly Regex SafeDistro = new("^[A-Za-z0-9][A-Za-z0-9._-]{0,79}$", RegexOptions.CultureInvariant);
    private static readonly Regex SensitiveEnvironment = new("(?:SECRET|TOKEN|PASSWORD|CREDENTIAL|PRIVATE_KEY|API_KEY|JWT|NONCE)", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);
    private readonly string _wslExecutable;
    private Process? _bootstrap;
    private WslCoreClient? _client;
    private byte[]? _secret;
    private bool _disposed;

    public WslCoreSupervisor(string? wslExecutable = null)
    {
        _wslExecutable = wslExecutable ?? ResolveWslExecutable();
    }

    public async Task<IReadOnlyList<WslCoreDistribution>> ListInstalledAsync(CancellationToken cancellationToken = default)
    {
        EnsureWslExists();
        var result = await RunCaptureAsync(["--list", "--verbose"], TimeSpan.FromSeconds(8), cancellationToken);
        if (result.ExitCode != 0) throw new WslCoreProtocolException("WSL_UNAVAILABLE", "WSL distribution inventory is unavailable.");
        return ParseVerboseList(result.Stdout);
    }

    public async Task<bool> IsCoreAvailableAsync(string distribution, string linuxCorePath, CancellationToken cancellationToken = default)
    {
        ValidateDistribution(distribution);
        ValidateLinuxPath(linuxCorePath);
        EnsureWslExists();
        var result = await RunCaptureAsync(["--distribution", distribution, "--exec", "/usr/bin/test", "-x", linuxCorePath], TimeSpan.FromSeconds(8), cancellationToken);
        return result.ExitCode == 0;
    }

    public async Task<WslCoreClient> StartAsync(WslCoreSupervisorOptions options, CancellationToken cancellationToken = default)
    {
        ObjectDisposedException.ThrowIf(_disposed, this);
        if (_bootstrap is not null) throw new InvalidOperationException("WSL core is already started.");
        if (Environment.GetEnvironmentVariable("CLOUDOS_WSL_CORE_FOUNDATION") != "1")
            throw new WslCoreProtocolException("FEATURE_DISABLED", "WSL core foundation feature flag is disabled.");
        if (!options.AllowBootstrap)
            throw new WslCoreProtocolException("BOOTSTRAP_DENIED", "Guest bootstrap was not authorized by the caller.");
        ValidateDistribution(options.Distribution);
        ValidateLinuxPath(options.LinuxCorePath);
        EnsureWslExists();
        var installed = await ListInstalledAsync(cancellationToken);
        var selected = installed.FirstOrDefault(item => string.Equals(item.Name, options.Distribution, StringComparison.OrdinalIgnoreCase));
        if (selected is null)
            throw new WslCoreProtocolException("DISTRO_NOT_INSTALLED", "Requested WSL distribution is not installed.");
        if (selected.Version != 2)
            throw new WslCoreProtocolException("DISTRO_NOT_WSL2", "Requested distribution is not running under WSL2.");
        if (!await IsCoreAvailableAsync(options.Distribution, options.LinuxCorePath, cancellationToken))
            throw new WslCoreProtocolException("CORE_NOT_AVAILABLE", "cloudos-core executable is not available in the selected distribution.");

        _secret = RandomNumberGenerator.GetBytes(WslCoreProtocol.SecretBytes);
        var startInfo = BuildBootstrapStartInfo(_wslExecutable, options.Distribution, options.LinuxCorePath);
        _bootstrap = new Process { StartInfo = startInfo, EnableRaisingEvents = true };
        try
        {
            if (!_bootstrap.Start()) throw new WslCoreProtocolException("BOOTSTRAP_FAILED", "WSL core bootstrap could not be started.");
            using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
            timeout.CancelAfter(TimeSpan.FromSeconds(20));
            await _bootstrap.StandardInput.WriteLineAsync(Convert.ToBase64String(_secret).AsMemory(), timeout.Token);
            await _bootstrap.StandardInput.FlushAsync(timeout.Token);
            _bootstrap.StandardInput.Close();
            var line = await _bootstrap.StandardOutput.ReadLineAsync(timeout.Token);
            if (string.IsNullOrWhiteSpace(line))
                throw new WslCoreProtocolException("BOOTSTRAP_FAILED", "Guest bootstrap did not return an endpoint.");
            var bootstrap = JsonSerializer.Deserialize<BootstrapRecord>(line)
                ?? throw new WslCoreProtocolException("BOOTSTRAP_FAILED", "Guest bootstrap endpoint is invalid.");
            if (bootstrap.Protocol != WslCoreProtocol.Version || bootstrap.Port is < 1 or > 65535 || bootstrap.Pid <= 0)
                throw new WslCoreProtocolException("BOOTSTRAP_FAILED", "Guest bootstrap endpoint failed validation.");
            _client = await WslCoreClient.ConnectAuthenticatedAsync(bootstrap.Port, _secret, timeout.Token);
            return _client;
        }
        catch
        {
            await StopBootstrapProcessAsync();
            ZeroSecret();
            throw;
        }
    }

    public async Task StopAsync(CancellationToken cancellationToken = default)
    {
        if (_client is not null)
        {
            try { await _client.ShutdownAsync(cancellationToken); }
            catch (Exception error) when (error is IOException or SocketException or WslCoreProtocolException or OperationCanceledException) { }
            await _client.DisposeAsync();
            _client = null;
        }
        await StopBootstrapProcessAsync(cancellationToken);
        ZeroSecret();
    }

    private async Task StopBootstrapProcessAsync(CancellationToken cancellationToken = default)
    {
        var process = _bootstrap;
        _bootstrap = null;
        if (process is null) return;
        try
        {
            if (!process.HasExited)
            {
                using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
                timeout.CancelAfter(TimeSpan.FromSeconds(5));
                try { await process.WaitForExitAsync(timeout.Token); }
                catch (OperationCanceledException)
                {
                    if (!process.HasExited) process.Kill(entireProcessTree: false);
                }
            }
            if (!process.HasExited) await process.WaitForExitAsync(CancellationToken.None);
        }
        finally { process.Dispose(); }
    }

    internal static ProcessStartInfo BuildBootstrapStartInfo(string wslExecutable, string distribution, string linuxCorePath)
    {
        ValidateDistribution(distribution);
        ValidateLinuxPath(linuxCorePath);
        var info = new ProcessStartInfo
        {
            FileName = wslExecutable,
            UseShellExecute = false,
            CreateNoWindow = true,
            RedirectStandardInput = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true
        };
        info.ArgumentList.Add("--distribution");
        info.ArgumentList.Add(distribution);
        info.ArgumentList.Add("--exec");
        info.ArgumentList.Add(linuxCorePath);
        info.ArgumentList.Add("serve");
        foreach (var key in info.Environment.Keys.ToArray())
        {
            if (SensitiveEnvironment.IsMatch(key)) info.Environment.Remove(key);
        }
        return info;
    }

    internal static IReadOnlyList<WslCoreDistribution> ParseVerboseList(string output)
    {
        var normalized = output.Replace("\0", string.Empty, StringComparison.Ordinal);
        var distributions = new List<WslCoreDistribution>();
        foreach (var rawLine in normalized.Split(['\r', '\n'], StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries))
        {
            var line = rawLine.Trim();
            var isDefault = line.StartsWith('*');
            if (isDefault) line = line[1..].TrimStart();
            var match = Regex.Match(line, "^(?<name>[A-Za-z0-9][A-Za-z0-9._-]{0,79})\\s+.+?\\s+(?<version>[12])$", RegexOptions.CultureInvariant);
            if (!match.Success) continue;
            if (!int.TryParse(match.Groups["version"].Value, out var version)) continue;
            var name = match.Groups["name"].Value;
            if (distributions.Any(item => string.Equals(item.Name, name, StringComparison.OrdinalIgnoreCase))) continue;
            distributions.Add(new WslCoreDistribution(name, version, isDefault));
        }
        return distributions;
    }

    private async Task<CaptureResult> RunCaptureAsync(IReadOnlyList<string> arguments, TimeSpan timeout, CancellationToken cancellationToken)
    {
        var info = new ProcessStartInfo
        {
            FileName = _wslExecutable,
            UseShellExecute = false,
            CreateNoWindow = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true
        };
        foreach (var argument in arguments) info.ArgumentList.Add(argument);
        foreach (var key in info.Environment.Keys.ToArray())
        {
            if (SensitiveEnvironment.IsMatch(key)) info.Environment.Remove(key);
        }
        using var process = new Process { StartInfo = info };
        try
        {
            if (!process.Start()) return new CaptureResult(-1, string.Empty);
        }
        catch (Exception error) when (error is System.ComponentModel.Win32Exception or InvalidOperationException)
        {
            throw new WslCoreProtocolException("WSL_UNAVAILABLE", "WSL process could not be started.");
        }
        using var bounded = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        bounded.CancelAfter(timeout);
        var stdoutTask = process.StandardOutput.ReadToEndAsync(bounded.Token);
        var stderrTask = process.StandardError.ReadToEndAsync(bounded.Token);
        try { await process.WaitForExitAsync(bounded.Token); }
        catch (OperationCanceledException)
        {
            if (!process.HasExited) process.Kill(entireProcessTree: false);
            throw new WslCoreProtocolException("WSL_TIMEOUT", "WSL command timed out.");
        }
        var stdout = await stdoutTask;
        _ = await stderrTask;
        return new CaptureResult(process.ExitCode, stdout);
    }

    private void EnsureWslExists()
    {
        if (!OperatingSystem.IsWindows() || !File.Exists(_wslExecutable))
            throw new WslCoreProtocolException("WSL_NOT_FOUND", "wsl.exe is not available on this host.");
    }

    internal static void ValidateDistribution(string distribution)
    {
        if (!SafeDistro.IsMatch(distribution ?? string.Empty))
            throw new ArgumentException("Invalid WSL distribution identifier.", nameof(distribution));
    }

    internal static void ValidateLinuxPath(string path)
    {
        if (string.IsNullOrWhiteSpace(path) || !path.StartsWith('/', StringComparison.Ordinal) || path.Length > 4096 || path.Contains('\0'))
            throw new ArgumentException("Invalid Linux cloudos-core path.", nameof(path));
    }

    private static string ResolveWslExecutable()
    {
        if (!OperatingSystem.IsWindows()) return "wsl.exe";
        var windows = Environment.GetEnvironmentVariable("WINDIR");
        if (string.IsNullOrWhiteSpace(windows)) windows = @"C:\Windows";
        return Path.Combine(windows, "System32", "wsl.exe");
    }

    private void ZeroSecret()
    {
        if (_secret is null) return;
        CryptographicOperations.ZeroMemory(_secret);
        _secret = null;
    }

    public async ValueTask DisposeAsync()
    {
        if (_disposed) return;
        await StopAsync(CancellationToken.None);
        _disposed = true;
    }

    private sealed class BootstrapRecord
    {
        [System.Text.Json.Serialization.JsonPropertyName("protocol")] public int Protocol { get; init; }
        [System.Text.Json.Serialization.JsonPropertyName("port")] public int Port { get; init; }
        [System.Text.Json.Serialization.JsonPropertyName("pid")] public int Pid { get; init; }
    }

    private sealed record CaptureResult(int ExitCode, string Stdout);
}
