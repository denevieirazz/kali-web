using System.Diagnostics;
using System.IO;
using Microsoft.Web.WebView2.Core;

namespace CloudOS.Bootstrap;

public sealed record PrerequisiteItem(string Id, string Label, string State, string Detail, bool RequiredForFull, bool RequiredForWebOnly);

public sealed record PrerequisiteReport(IReadOnlyList<PrerequisiteItem> Items)
{
    private static bool IsReadyState(string state) => state is "pronto" or "opcional";
    public bool FullReady => Items.Where(item => item.RequiredForFull).All(item => IsReadyState(item.State));
    public bool WebOnlyReady => Items.Where(item => item.RequiredForWebOnly).All(item => IsReadyState(item.State));
}

public static class PrerequisiteProbe
{
    public static async Task<PrerequisiteReport> RunAsync(BootstrapOptions options, CancellationToken cancellationToken = default)
    {
        var root = DistributionEnvironment.ResolvePackageRoot(options);
        var items = new List<PrerequisiteItem>();

        var webViewVersion = ProbeWebView2();
        items.Add(new("webview2", "Microsoft Edge WebView2", webViewVersion is null ? "requer ação do usuário" : "pronto", webViewVersion ?? "Runtime Evergreen não encontrado.", true, false));

        var hostExists = File.Exists(options.HostPath);
        items.Add(new("native-host", "Native Host", hostExists ? "pronto" : "indisponível", hostExists ? "CloudOS.Host.exe localizado." : "CloudOS.Host.exe não foi localizado.", true, false));

        var nodePath = ResolveNode(options, root);
        var nodeReady = nodePath is not null;
        items.Add(new("node-runtime", "Runtime Node", nodeReady ? "pronto" : "incompatível", nodeReady ? $"Runtime empacotado: {Path.GetFileName(nodePath)}" : "Runtime Node empacotado não encontrado.", true, true));

        var backendReady = ResolveBackend(root) is not null;
        items.Add(new("backend", "Backend local", backendReady ? "pronto" : "incompatível", backendReady ? "Bundle de produção localizado." : "Bundle backend ausente.", true, true));

        var frontendReady = ResolveFrontend(root) is not null;
        items.Add(new("frontend", "Frontend de produção", frontendReady ? "pronto" : "incompatível", frontendReady ? "Build web de produção localizado." : "Build web ausente.", true, true));

        var freeBytes = GetFreeBytes(root);
        var enoughSpace = freeBytes >= 2L * 1024 * 1024 * 1024;
        items.Add(new("disk", "Espaço disponível", enoughSpace ? "pronto" : "requer ação do usuário", $"{freeBytes / 1024d / 1024d / 1024d:F1} GB livres; mínimo recomendado 2 GB.", true, true));

        var pwsh = FindExecutable("pwsh.exe");
        items.Add(new("powershell", "PowerShell 7", pwsh is null ? "opcional" : "pronto", pwsh is null ? "Não localizado; recursos que dependem dele ficam indisponíveis." : "PowerShell 7 disponível.", false, false));

        var wsl = await ProbeProcessAsync("wsl.exe", new[] { "--version" }, cancellationToken);
        var wslReady = wsl.ExitCode == 0;
        items.Add(new("wsl2", "WSL2", wslReady ? "pronto" : "opcional", wslReady ? FirstLine(wsl.Output, "WSL disponível.") : "WSL não está disponível; o CloudOS não fará alterações automaticamente.", false, false));

        var distros = wslReady ? await ProbeProcessAsync("wsl.exe", new[] { "--list", "--verbose" }, cancellationToken) : ProcessProbeResult.Unavailable;
        var kaliReady = distros.ExitCode == 0 && distros.Output.Contains("kali-linux", StringComparison.OrdinalIgnoreCase);
        items.Add(new("kali-linux", "Kali Linux", kaliReady ? "pronto" : "opcional", kaliReady ? "Distribuição kali-linux detectada." : "kali-linux não detectada; instalação permanece a cargo do usuário.", false, false));

        var corePath = Path.Combine(root, "runtime", "cloudos-core");
        var coreReady = File.Exists(corePath);
        items.Add(new("wsl-core", "WSL Core", coreReady ? "pronto" : "opcional", coreReady ? "Payload Linux localizado." : "Payload WSL Core não incluído neste layout.", false, false));
        items.Add(new("browser", "Navegador CloudOS", webViewVersion is null ? "requer ação do usuário" : "pronto", webViewVersion is null ? "Requer WebView2 para o modo Full." : "WebView2 disponível.", true, false));
        items.Add(new("terminal", "Terminal", wslReady && kaliReady ? "pronto" : "opcional", wslReady && kaliReady ? "Linux/WSL disponível." : "Terminal Linux ficará limitado até WSL/Kali estarem disponíveis.", false, false));
        items.Add(new("files-windows", "Files Windows", "pronto", "Acesso continua dependente de concessão explícita do usuário.", false, false));
        items.Add(new("files-linux", "Files Linux", wslReady && kaliReady ? "pronto" : "opcional", wslReady && kaliReady ? "Linux Home disponível mediante sessão autenticada." : "Linux Home indisponível sem WSL/Kali.", false, false));

        return new PrerequisiteReport(items);
    }

    public static string? ResolveNode(BootstrapOptions options, string root)
    {
        var candidates = new[] { options.NodePath, Path.Combine(root, "runtime", "node.exe"), Path.Combine(AppContext.BaseDirectory, "runtime", "node.exe") };
        return candidates.Where(path => !string.IsNullOrWhiteSpace(path)).Select(path => Path.GetFullPath(path!)).FirstOrDefault(File.Exists);
    }

    public static string? ResolveBackend(string root)
    {
        var candidates = new[] { Path.Combine(root, "agent", "backend", "src", "server.js"), Path.Combine(root, "backend", "src", "server.js") };
        return candidates.FirstOrDefault(File.Exists);
    }

    public static string? ResolveFrontend(string root)
    {
        var candidates = new[] { Path.Combine(root, "web"), Path.Combine(root, "frontend", "dist") };
        return candidates.FirstOrDefault(path => File.Exists(Path.Combine(path, "index.html")));
    }

    private static string? ProbeWebView2()
    {
        try { return CoreWebView2Environment.GetAvailableBrowserVersionString(); }
        catch (WebView2RuntimeNotFoundException) { return null; }
        catch { return null; }
    }

    private static long GetFreeBytes(string path)
    {
        try
        {
            var root = Path.GetPathRoot(Path.GetFullPath(path));
            return root is null ? 0 : new DriveInfo(root).AvailableFreeSpace;
        }
        catch { return 0; }
    }

    private static string? FindExecutable(string name)
    {
        foreach (var directory in (Environment.GetEnvironmentVariable("PATH") ?? string.Empty).Split(Path.PathSeparator, StringSplitOptions.RemoveEmptyEntries))
        {
            try
            {
                var candidate = Path.Combine(directory.Trim('"'), name);
                if (File.Exists(candidate)) return candidate;
            }
            catch { }
        }
        return null;
    }

    private static async Task<ProcessProbeResult> ProbeProcessAsync(string file, IReadOnlyList<string> args, CancellationToken cancellationToken)
    {
        try
        {
            var start = new ProcessStartInfo { FileName = file, UseShellExecute = false, CreateNoWindow = true, RedirectStandardOutput = true, RedirectStandardError = true };
            foreach (var arg in args) start.ArgumentList.Add(arg);
            using var process = Process.Start(start);
            if (process is null) return ProcessProbeResult.Unavailable;
            using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
            timeout.CancelAfter(TimeSpan.FromSeconds(6));
            var stdout = process.StandardOutput.ReadToEndAsync(timeout.Token);
            var stderr = process.StandardError.ReadToEndAsync(timeout.Token);
            await process.WaitForExitAsync(timeout.Token);
            return new ProcessProbeResult(process.ExitCode, (await stdout) + Environment.NewLine + (await stderr));
        }
        catch { return ProcessProbeResult.Unavailable; }
    }

    private static string FirstLine(string text, string fallback)
        => text.Split(new[] { '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries).FirstOrDefault()?.Trim() ?? fallback;

    private sealed record ProcessProbeResult(int ExitCode, string Output)
    {
        public static ProcessProbeResult Unavailable { get; } = new(-1, string.Empty);
    }
}
