using System.Text.Json;
using System.Text.RegularExpressions;
using System.Windows;
using System.Windows.Media;
using System.Windows.Threading;
using CloudOS.Host.Browser;
using Microsoft.Web.WebView2.Core;

namespace CloudOS.Browser.TestHost;

internal static class Program
{
    [STAThread]
    public static int Main(string[] args)
    {
        var options = Parse(args);
        if (!options.TryGetValue("debug-port", out var portText) ||
            !int.TryParse(portText, out var debugPort) || debugPort is < 1 or > 65535)
            throw new ArgumentException("--debug-port é obrigatório.");

        var url = options.GetValueOrDefault("url") ?? "about:blank";
        var root = Path.GetFullPath(options.GetValueOrDefault("root") ??
            Path.Combine(Path.GetTempPath(), "cloudos-browser-test", Guid.NewGuid().ToString("N")));
        Directory.CreateDirectory(root);
        var udf = Path.Combine(root, "WebView2");
        var downloadsRoot = Path.Combine(root, "downloads");
        Directory.CreateDirectory(downloadsRoot);
        var statePath = Path.Combine(root, "browser-state.v1.json");
        var backendOrigin = new Uri(options.GetValueOrDefault("backend-origin") ?? "http://127.0.0.1:65534/");
        var readyFile = options.GetValueOrDefault("ready-file");
        var controlFile = options.GetValueOrDefault("control-file");
        var statusFile = options.GetValueOrDefault("status-file");
        var logFile = Path.GetFullPath(options.GetValueOrDefault("log-file") ?? Path.Combine(root, "testhost.log"));

        void Log(string code, string? detail = null)
        {
            var safeDetail = Sanitize(detail, root);
            var line = $"{DateTimeOffset.UtcNow:O} {code}{(safeDetail.Length == 0 ? string.Empty : " " + safeDetail)}{Environment.NewLine}";
            try
            {
                Directory.CreateDirectory(Path.GetDirectoryName(logFile) ?? root);
                File.AppendAllText(logFile, line);
            }
            catch (Exception error) when (error is IOException or UnauthorizedAccessException)
            {
                Console.Error.WriteLine($"TESTHOST_LOG_FAILED {error.GetType().Name}");
            }
        }

        Log("START", $"pid={Environment.ProcessId}");

        var app = new Application { ShutdownMode = ShutdownMode.OnLastWindowClose };
        app.Resources["CloudOsBackground"] = new SolidColorBrush(Color.FromRgb(8, 13, 24));
        app.Resources["CloudOsPanel"] = new SolidColorBrush(Color.FromRgb(17, 26, 43));
        app.Resources["CloudOsAccent"] = new SolidColorBrush(Color.FromRgb(91, 146, 238));
        app.DispatcherUnhandledException += (_, eventArgs) =>
        {
            Log("DISPATCHER_UNHANDLED", eventArgs.Exception.ToString());
            eventArgs.Handled = true;
            app.Shutdown(3);
        };
        app.Exit += (_, eventArgs) => Log("EXIT", $"code={eventArgs.ApplicationExitCode}");

        app.Startup += async (_, _) =>
        {
            DispatcherTimer? controlTimer = null;
            try
            {
                Log("ENVIRONMENT_CREATE_BEGIN");
                var environmentOptions = new CoreWebView2EnvironmentOptions($"--remote-debugging-port={debugPort}");
                var environment = await CoreWebView2Environment.CreateAsync(null, udf, environmentOptions);
                Log("ENVIRONMENT_READY");

                var policy = new BrowserPolicy(new Uri("https://cloudos.local/"), backendOrigin);
                var store = new BrowserStateStore(statePath);
                var downloadManager = new BrowserDownloadManager((_, suggestedName) =>
                    Path.Combine(downloadsRoot, UniqueSafeFileName(downloadsRoot, suggestedName)));
                var window = new BrowserWindow(environment, policy, store, developerMode: true, downloadManager);

                void WriteStatus(bool closed = false)
                {
                    if (string.IsNullOrWhiteSpace(statusFile)) return;
                    try
                    {
                        var snapshot = window.GetDiagnosticSnapshot();
                        var status = new
                        {
                            closed,
                            snapshot.TabCount,
                            snapshot.ActiveDownloadCount,
                            snapshot.ActiveErrorCode,
                            snapshot.ActiveIsNewTab,
                            snapshot.Closing
                        };
                        Directory.CreateDirectory(Path.GetDirectoryName(statusFile) ?? root);
                        File.WriteAllText(statusFile, JsonSerializer.Serialize(status));
                    }
                    catch (Exception error) when (error is IOException or UnauthorizedAccessException or InvalidOperationException)
                    {
                        Log("STATUS_WRITE_FAILED", error.GetType().Name);
                    }
                }

                window.Closed += (_, _) =>
                {
                    controlTimer?.Stop();
                    WriteStatus(closed: true);
                    Log("BROWSER_WINDOW_CLOSED");
                };
                await window.InitializeAsync(url);
                window.Show();
                window.Activate();
                Log("BROWSER_WINDOW_READY");
                WriteStatus();

                if (!string.IsNullOrWhiteSpace(controlFile) || !string.IsNullOrWhiteSpace(statusFile))
                {
                    controlTimer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(200) };
                    controlTimer.Tick += (_, _) =>
                    {
                        if (!window.IsLoaded) return;
                        WriteStatus();
                        if (string.IsNullOrWhiteSpace(controlFile) || !File.Exists(controlFile)) return;
                        string command;
                        try
                        {
                            command = File.ReadAllText(controlFile).Trim();
                            File.Delete(controlFile);
                        }
                        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
                        {
                            Log("CONTROL_READ_FAILED", error.GetType().Name);
                            return;
                        }

                        switch (command)
                        {
                            case "cancel-downloads":
                                Log("CONTROL_CANCEL_DOWNLOADS", $"count={window.CancelDownloads()}");
                                WriteStatus();
                                break;
                            case "close-browser":
                                Log("CONTROL_CLOSE_BROWSER");
                                window.CloseForHostShutdown();
                                break;
                            case "snapshot":
                                Log("CONTROL_SNAPSHOT");
                                WriteStatus();
                                break;
                            default:
                                Log("CONTROL_UNKNOWN");
                                break;
                        }
                    };
                    controlTimer.Start();
                }

                if (!string.IsNullOrWhiteSpace(readyFile))
                {
                    Directory.CreateDirectory(Path.GetDirectoryName(readyFile) ?? root);
                    File.WriteAllText(readyFile, "ready");
                }
            }
            catch (Exception error)
            {
                controlTimer?.Stop();
                var safe = Sanitize(error.ToString(), root);
                Log("STARTUP_FAILED", safe);
                if (!string.IsNullOrWhiteSpace(readyFile))
                {
                    try { File.WriteAllText(readyFile + ".error", safe); }
                    catch (Exception writeError) when (writeError is IOException or UnauthorizedAccessException)
                    {
                        Log("ERROR_FILE_WRITE_FAILED", writeError.GetType().Name);
                    }
                }
                app.Shutdown(2);
            }
        };

        return app.Run();
    }

    private static Dictionary<string, string> Parse(string[] args)
    {
        var values = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        for (var i = 0; i < args.Length; i++)
        {
            if (!args[i].StartsWith("--", StringComparison.Ordinal)) continue;
            var key = args[i][2..];
            if (i + 1 < args.Length && !args[i + 1].StartsWith("--", StringComparison.Ordinal))
                values[key] = args[++i];
            else
                values[key] = "1";
        }
        return values;
    }

    private static string UniqueSafeFileName(string directory, string suggestedName)
    {
        var invalid = Path.GetInvalidFileNameChars().ToHashSet();
        var source = Path.GetFileName(suggestedName);
        var safe = new string(source.Where(character => !invalid.Contains(character) && !char.IsControl(character)).ToArray()).Trim();
        if (safe.Length == 0) safe = "download.bin";
        if (safe.Length > 128) safe = safe[..128];
        var candidate = safe;
        var counter = 1;
        while (File.Exists(Path.Combine(directory, candidate)))
        {
            var extension = Path.GetExtension(safe);
            var stem = Path.GetFileNameWithoutExtension(safe);
            candidate = $"{stem}-{counter++}{extension}";
        }
        return candidate;
    }

    private static string Sanitize(string? value, string root)
    {
        if (string.IsNullOrWhiteSpace(value)) return string.Empty;
        var sanitized = value.Replace(root, "<temp>", StringComparison.OrdinalIgnoreCase);
        sanitized = Regex.Replace(
            sanitized,
            "(?i)(authorization|bearer|jwt|token|password|passwd|secret|recovery[_-]?code|api[_-]?key)(\\s*[:=]\\s*|\\s+)[^\\s,;]+",
            "$1=<redacted>",
            RegexOptions.CultureInvariant);
        return sanitized.Length <= 32_768 ? sanitized : sanitized[..32_768] + "<truncated>";
    }
}
