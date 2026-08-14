using System.Windows;
using System.Windows.Media;
using CloudOS.Host.Browser;
using Microsoft.Web.WebView2.Core;

namespace CloudOS.Browser.TestHost;

internal static class Program
{
    [STAThread]
    public static int Main(string[] args)
    {
        var options = Parse(args);
        if (!options.TryGetValue("debug-port", out var portText) || !int.TryParse(portText, out var debugPort) || debugPort is < 1 or > 65535)
            throw new ArgumentException("--debug-port é obrigatório.");
        var url = options.GetValueOrDefault("url") ?? "about:blank";
        var root = options.GetValueOrDefault("root") ?? Path.Combine(Path.GetTempPath(), "cloudos-browser-test", Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        var udf = Path.Combine(root, "WebView2");
        var statePath = Path.Combine(root, "browser-state.v1.json");
        var backendOrigin = new Uri(options.GetValueOrDefault("backend-origin") ?? "http://127.0.0.1:65534/");
        var readyFile = options.GetValueOrDefault("ready-file");

        var app = new Application { ShutdownMode = ShutdownMode.OnLastWindowClose };
        app.Resources["CloudOsBackground"] = new SolidColorBrush(Color.FromRgb(8, 13, 24));
        app.Resources["CloudOsPanel"] = new SolidColorBrush(Color.FromRgb(17, 26, 43));
        app.Resources["CloudOsAccent"] = new SolidColorBrush(Color.FromRgb(91, 146, 238));

        app.Startup += async (_, _) =>
        {
            try
            {
                var environmentOptions = new CoreWebView2EnvironmentOptions($"--remote-debugging-port={debugPort}");
                var environment = await CoreWebView2Environment.CreateAsync(null, udf, environmentOptions);
                var policy = new BrowserPolicy(new Uri("https://cloudos.local/"), backendOrigin);
                var store = new BrowserStateStore(statePath);
                var window = new BrowserWindow(environment, policy, store, developerMode: true);
                window.Show();
                await window.InitializeAsync(url);
                if (!string.IsNullOrWhiteSpace(readyFile))
                {
                    Directory.CreateDirectory(Path.GetDirectoryName(readyFile) ?? root);
                    File.WriteAllText(readyFile, $"ready\n{environment.UserDataFolder}");
                }
            }
            catch (Exception error)
            {
                if (!string.IsNullOrWhiteSpace(readyFile)) File.WriteAllText(readyFile + ".error", error.ToString());
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
            if (i + 1 < args.Length && !args[i + 1].StartsWith("--", StringComparison.Ordinal)) values[key] = args[++i];
            else values[key] = "1";
        }
        return values;
    }
}
