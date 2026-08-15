using System.Drawing;
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Interop;
using System.Windows.Media;
using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.Wpf;
using DrawingColor = System.Drawing.Color;
using WpfPoint = System.Windows.Point;
using WpfRect = System.Windows.Rect;

namespace CloudOS.Browser.PhysicalProbe;

internal static class SurfaceVisualDiagnostics
{
    internal const double BoundsTolerancePixels = 1.5d;
    private const string SentinelTitle = "CloudOS Surface Sentinel";
    private const string SentinelElementId = "cloudos-surface-physical-probe";
    private static readonly BrowserSurfaceRgb SentinelColor = new(25, 50, 74);
    private static readonly ConditionalWeakTable<WebView2, SentinelState> SentinelStates = new();
    private static readonly ConditionalWeakTable<Window, ObservationHook> ObservationHooks = new();

    internal static SurfaceVisualReport EnsureMenuInsideWindow(Window window, FrameworkElement popupRoot)
    {
        window.UpdateLayout();
        popupRoot.UpdateLayout();
        var windowBounds = ScreenBounds(window);
        var popupBounds = ScreenBounds(popupRoot);
        EnsureInside(popupBounds, windowBounds, "menu-popup");
        return new SurfaceVisualReport
        {
            Stage = "menu",
            WindowBounds = ToReport(windowBounds),
            HubBounds = ToReport(popupBounds),
            DpiScale = Math.Round(VisualTreeHelper.GetDpi(window).DpiScaleX, 4)
        };
    }

    internal static async Task PrepareWebViewSentinelAsync(WebView2 webView)
    {
        var core = webView.CoreWebView2
            ?? throw new InvalidOperationException("webview-not-rendered: WebView2 não inicializado para a sentinela.");
        var state = SentinelStates.GetOrCreateValue(webView);
        state.NavigationCompleted = false;
        state.DocumentConfirmed = false;
        state.LastObservedSurface = null;

        var completion = new TaskCompletionSource<CoreWebView2NavigationCompletedEventArgs>(TaskCreationOptions.RunContinuationsAsynchronously);
        void OnNavigationCompleted(object? sender, CoreWebView2NavigationCompletedEventArgs e) => completion.TrySetResult(e);
        core.NavigationCompleted += OnNavigationCompleted;
        try
        {
            core.NavigateToString(SentinelHtml);
            CoreWebView2NavigationCompletedEventArgs result;
            try
            {
                result = await completion.Task.WaitAsync(TimeSpan.FromSeconds(8));
            }
            catch (TimeoutException)
            {
                throw new InvalidOperationException("sentinel-navigation-not-completed: NavigationCompleted não ocorreu no prazo do gate.");
            }

            state.NavigationCompleted = result.IsSuccess;
            if (!result.IsSuccess)
                throw new InvalidOperationException($"sentinel-navigation-not-completed: status={result.WebErrorStatus}.");

            state.DocumentConfirmed = await ConfirmSentinelDocumentAsync(core);
            if (!state.DocumentConfirmed)
                throw new InvalidOperationException("sentinel-navigation-not-completed: documento sentinela não confirmou título, marcador e cor esperados.");
        }
        finally
        {
            core.NavigationCompleted -= OnNavigationCompleted;
        }

        InstallObservationHook(webView, state);
    }

    internal static async Task<CoreWebView2BrowserExtension> AddUnmanagedProbeExtensionAsync(
        CoreWebView2Profile profile,
        string tempRoot)
    {
        var source = Path.Combine(tempRoot, "unmanaged-webview-extension-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(source);
        await File.WriteAllTextAsync(
            Path.Combine(source, "manifest.json"),
            System.Text.Json.JsonSerializer.Serialize(new
            {
                manifest_version = 3,
                name = "WebView2 Internal Probe Component",
                version = "1.0.0"
            }));
        await File.WriteAllTextAsync(Path.Combine(source, "service-worker.js"), "void 0;");
        return await profile.AddBrowserExtensionAsync(source);
    }

    internal static SurfaceVisualReport EnsureHubAndWebView(
        Window window,
        Border hub,
        WebView2 webView,
        string surfaceName)
    {
        window.UpdateLayout();
        hub.UpdateLayout();
        webView.UpdateLayout();

        var state = SentinelStates.GetOrCreateValue(webView);
        var report = MeasureHubAndWebView(window, hub, webView, surfaceName, state);
        ProbeRunReport.Current?.RegisterSurface(surfaceName, report, finalMeasurement: true);

        // A captura da etapa é produzida antes de qualquer exceção deste gate.
        TryCaptureStageArtifact(window, surfaceName);

        if (!string.IsNullOrWhiteSpace(report.FailureClassification))
            throw new InvalidOperationException($"{report.FailureClassification}: {report.FailureDetail}");

        return report;
    }

    internal static void EnsureElementVisibleInScrollViewer(ScrollViewer scroll, FrameworkElement element, string label)
    {
        scroll.UpdateLayout();
        element.UpdateLayout();
        var elementBounds = element.TransformToAncestor(scroll).TransformBounds(new WpfRect(0, 0, element.ActualWidth, element.ActualHeight));
        var viewport = new WpfRect(0, 0, scroll.ViewportWidth, scroll.ViewportHeight);
        if (elementBounds.Top < viewport.Top - 1 || elementBounds.Bottom > viewport.Bottom + 1)
            throw new InvalidOperationException($"{label}: item focado não foi trazido para o viewport rolável.");
    }

    internal static T? FindDescendant<T>(DependencyObject root) where T : DependencyObject
    {
        var count = VisualTreeHelper.GetChildrenCount(root);
        for (var index = 0; index < count; index++)
        {
            var child = VisualTreeHelper.GetChild(root, index);
            if (child is T match) return match;
            var nested = FindDescendant<T>(child);
            if (nested is not null) return nested;
        }
        return null;
    }

    internal static IReadOnlyList<T> FindDescendants<T>(DependencyObject root) where T : DependencyObject
    {
        var result = new List<T>();
        AppendDescendants(root, result);
        return result;
    }

    private static void InstallObservationHook(WebView2 webView, SentinelState state)
    {
        if (Window.GetWindow(webView) is not Window window || ObservationHooks.TryGetValue(window, out _))
            return;
        if (window.FindName("HubPanel") is not Border hub || window.FindName("HubTitle") is not TextBlock title)
            return;

        var hook = new ObservationHook(window, hub, title, webView, state);
        ObservationHooks.Add(window, hook);
        hub.LayoutUpdated += hook.OnLayoutUpdated;
        window.Closed += hook.OnWindowClosed;
    }

    private static async Task<bool> ConfirmSentinelDocumentAsync(CoreWebView2 core)
    {
        const string script = """
            (() => {
              const node = document.getElementById('cloudos-surface-physical-probe');
              if (!node || document.title !== 'CloudOS Surface Sentinel') return false;
              const style = getComputedStyle(node);
              const rect = node.getBoundingClientRect();
              return node.dataset.cloudosSentinel === 'v2' &&
                     style.backgroundColor === 'rgb(25, 50, 74)' &&
                     rect.width >= Math.max(1, innerWidth - 2) &&
                     rect.height >= Math.max(1, innerHeight - 2) &&
                     document.readyState === 'complete';
            })();
            """;
        var result = await core.ExecuteScriptAsync(script);
        return string.Equals(result.Trim(), "true", StringComparison.OrdinalIgnoreCase);
    }

    private static SurfaceVisualReport MeasureHubAndWebView(
        Window window,
        Border hub,
        WebView2 webView,
        string surfaceName,
        SentinelState state)
    {
        var dpi = VisualTreeHelper.GetDpi(window);
        var windowPixels = ScreenBounds(window);
        var hubPixels = SafeScreenBounds(hub);
        var webPixels = SafeScreenBounds(webView);
        var webDip = BoundsRelativeToWindow(window, webView);
        var webVisible = webView.Visibility == Visibility.Visible && webView.IsVisible && webView.ActualWidth >= 300 && webView.ActualHeight >= 240;

        var scaledDip = BrowserSurfaceGeometry.ScaleDipRect(ToSurfaceRect(webDip), dpi.DpiScaleX, dpi.DpiScaleY);
        var clientOrigin = window.PointToScreen(new WpfPoint(0, 0));
        var expectedPixels = new BrowserSurfaceRect(
            clientOrigin.X + scaledDip.X,
            clientOrigin.Y + scaledDip.Y,
            scaledDip.Width,
            scaledDip.Height);
        var actualWebPixels = ToSurfaceRect(webPixels);
        var dpiMismatch = Math.Abs(expectedPixels.X - actualWebPixels.X) > 2.5 ||
                          Math.Abs(expectedPixels.Y - actualWebPixels.Y) > 2.5 ||
                          Math.Abs(expectedPixels.Width - actualWebPixels.Width) > 2.5 ||
                          Math.Abs(expectedPixels.Height - actualWebPixels.Height) > 2.5;

        var overlap = BrowserSurfaceGeometry.HorizontalOverlapPixels(actualWebPixels, ToSurfaceRect(hubPixels));
        var separation = BrowserSurfaceGeometry.SeparationPixels(actualWebPixels, ToSurfaceRect(hubPixels));
        BrowserSurfaceRect samplingRegion;
        IReadOnlyList<BrowserSurfacePoint> grid;
        try
        {
            samplingRegion = BrowserSurfaceGeometry.SelectInteriorRegion(actualWebPixels);
            grid = BrowserSurfaceGeometry.BuildSampleGrid(samplingRegion);
        }
        catch (ArgumentOutOfRangeException)
        {
            samplingRegion = default;
            grid = [];
        }

        var sampleReports = new List<SurfaceSamplePointReport>();
        var observed = new List<BrowserSurfaceRgb>();
        var captureUnavailable = false;
        var sampleOutside = false;
        var compositionReady = false;
        try
        {
            compositionReady = DwmFlush() == 0;
        }
        catch (DllNotFoundException)
        {
            captureUnavailable = true;
        }

        foreach (var point in grid)
        {
            var inside = point.X >= actualWebPixels.Left && point.X <= actualWebPixels.Right &&
                         point.Y >= actualWebPixels.Top && point.Y <= actualWebPixels.Bottom;
            if (!inside)
            {
                sampleOutside = true;
                continue;
            }

            try
            {
                var color = SampleScreenPixel(point.X, point.Y);
                var rgb = new BrowserSurfaceRgb(color.R, color.G, color.B);
                observed.Add(rgb);
                var matches = Math.Abs(rgb.R - SentinelColor.R) <= BrowserSurfaceGeometry.DefaultColorTolerance &&
                              Math.Abs(rgb.G - SentinelColor.G) <= BrowserSurfaceGeometry.DefaultColorTolerance &&
                              Math.Abs(rgb.B - SentinelColor.B) <= BrowserSurfaceGeometry.DefaultColorTolerance;
                var white = rgb.R >= 245 && rgb.G >= 245 && rgb.B >= 245;
                sampleReports.Add(new SurfaceSamplePointReport(
                    point.X,
                    point.Y,
                    new RgbReport(rgb.R, rgb.G, rgb.B),
                    matches,
                    white,
                    true));
            }
            catch (Exception error) when (error is System.ComponentModel.Win32Exception or ExternalException or ArgumentException)
            {
                captureUnavailable = true;
                break;
            }
        }

        BrowserSurfaceColorEvaluation evaluation = default;
        if (observed.Count > 0)
            evaluation = BrowserSurfaceGeometry.EvaluateColors(observed, SentinelColor);

        string? classification = null;
        string? detail = null;
        if (!state.NavigationCompleted)
            SetFailure("sentinel-navigation-not-completed", "NavigationCompleted da sentinela não foi confirmado.");
        else if (!state.DocumentConfirmed || !string.Equals(state.LastObservedSurface, surfaceName, StringComparison.Ordinal))
            SetFailure("sentinel-navigation-not-completed", "O documento sentinela não foi reconfirmado após abrir esta superfície.");
        else if (!webVisible)
            SetFailure("webview-not-rendered", "WebView2 está oculto ou sem área física renderizável.");
        else if (!BrowserSurfaceGeometry.Contains(ToSurfaceRect(windowPixels), actualWebPixels, BoundsTolerancePixels) ||
                 !BrowserSurfaceGeometry.Contains(ToSurfaceRect(windowPixels), ToSurfaceRect(hubPixels), BoundsTolerancePixels))
            SetFailure("sample-outside-webview", "Hub ou WebView2 extrapola os bounds físicos da BrowserWindow.");
        else if (dpiMismatch)
            SetFailure("dpi-coordinate-mismatch", "Bounds DIP convertidos pelo DPI real divergem dos bounds retornados por PointToScreen.");
        else if (overlap > BoundsTolerancePixels)
            SetFailure("hub-webview-overlap", $"Hub invade o WebView2 em {overlap:0.##} px.");
        else if (samplingRegion.Width <= 0 || samplingRegion.Height <= 0 || sampleOutside)
            SetFailure("sample-outside-webview", "A região ou um ponto da matriz de amostragem escapou do WebView2.");
        else if (captureUnavailable || !compositionReady || observed.Count != grid.Count)
            SetFailure("capture-unavailable", "A composição física ou a captura da matriz não pôde ser concluída.");
        else if (evaluation.WhiteBackgroundDetected)
            SetFailure("white-host-background-visible", $"Fundo branco ocupa {evaluation.WhitePixelRatio:P0} da região interna amostrada.");
        else if (!evaluation.MeetsExpectedColorRatio)
            SetFailure("unexpected-rendered-color", $"Somente {evaluation.MatchRatio:P0} da região corresponde à sentinela física.");

        return new SurfaceVisualReport
        {
            Stage = surfaceName,
            WindowBounds = ToReport(windowPixels),
            HubBounds = ToReport(hubPixels),
            WebViewBoundsDip = ToReport(webDip),
            WebViewBoundsPixels = ToReport(webPixels),
            DpiScale = Math.Round(dpi.DpiScaleX, 4),
            NavigationCompleted = state.NavigationCompleted,
            DocumentConfirmed = state.DocumentConfirmed && string.Equals(state.LastObservedSurface, surfaceName, StringComparison.Ordinal),
            SamplingRegion = samplingRegion.Width > 0 ? ToReport(samplingRegion) : null,
            SamplePoints = sampleReports,
            ExpectedColor = new RgbReport(SentinelColor.R, SentinelColor.G, SentinelColor.B),
            ObservedColors = observed.Select(color => new RgbReport(color.R, color.G, color.B)).ToArray(),
            MatchRatio = Math.Round(evaluation.MatchRatio, 4),
            WhitePixelRatio = Math.Round(evaluation.WhitePixelRatio, 4),
            OverlapPixels = Math.Round(overlap, 2),
            SeparationPixels = Math.Round(separation, 2),
            WebViewVisible = webVisible,
            FailureClassification = classification,
            FailureDetail = detail
        };

        void SetFailure(string code, string message)
        {
            if (classification is not null) return;
            classification = code;
            detail = message;
        }
    }

    private static void TryCaptureStageArtifact(Window window, string surfaceName)
    {
        var artifact = surfaceName switch
        {
            "downloads" => "14-downloads.png",
            "extensions" => "15-extensions.png",
            "settings" => "16-settings.png",
            _ => null
        };
        if (artifact is null) return;

        try
        {
            var output = ResolveOutputDirectory();
            Directory.CreateDirectory(output);
            var path = Path.Combine(output, artifact);
            CaptureWindowScreen(window, path);
            var report = ProbeRunReport.Current;
            if (report is not null && !report.Artifacts.Contains(artifact, StringComparer.Ordinal))
                report.Artifacts.Add(artifact);
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or System.ComponentModel.Win32Exception or ExternalException or InvalidOperationException)
        {
            // The regional sampling gate will classify capture-unavailable when the physical read itself is unavailable.
        }
    }

    private static string ResolveOutputDirectory()
    {
        var args = Environment.GetCommandLineArgs();
        for (var index = 0; index + 1 < args.Length; index++)
            if (string.Equals(args[index], "--output", StringComparison.Ordinal))
                return Path.GetFullPath(args[index + 1]);
        return Path.GetFullPath(Path.Combine(Environment.CurrentDirectory, "test-results", "native-browser-physical-ui"));
    }

    private static void CaptureWindowScreen(Window window, string path)
    {
        var hwnd = new WindowInteropHelper(window).Handle;
        if (hwnd == IntPtr.Zero || !GetWindowRect(hwnd, out var rect))
            throw new InvalidOperationException("capture-unavailable");
        var width = Math.Max(1, rect.Right - rect.Left);
        var height = Math.Max(1, rect.Bottom - rect.Top);
        using var bitmap = new Bitmap(width, height, System.Drawing.Imaging.PixelFormat.Format32bppArgb);
        using (var graphics = Graphics.FromImage(bitmap))
            graphics.CopyFromScreen(rect.Left, rect.Top, 0, 0, new System.Drawing.Size(width, height), CopyPixelOperation.SourceCopy);
        bitmap.Save(path, System.Drawing.Imaging.ImageFormat.Png);
    }

    private static void AppendDescendants<T>(DependencyObject root, List<T> result) where T : DependencyObject
    {
        var count = VisualTreeHelper.GetChildrenCount(root);
        for (var index = 0; index < count; index++)
        {
            var child = VisualTreeHelper.GetChild(root, index);
            if (child is T match) result.Add(match);
            AppendDescendants(child, result);
        }
    }

    private static WpfRect BoundsRelativeToWindow(Window window, FrameworkElement element)
    {
        try
        {
            return element.TransformToAncestor(window).TransformBounds(new WpfRect(0, 0, element.ActualWidth, element.ActualHeight));
        }
        catch (InvalidOperationException)
        {
            return WpfRect.Empty;
        }
    }

    private static WpfRect SafeScreenBounds(FrameworkElement element)
    {
        try { return ScreenBounds(element); }
        catch (InvalidOperationException) { return WpfRect.Empty; }
    }

    private static WpfRect ScreenBounds(FrameworkElement element)
    {
        var topLeft = element.PointToScreen(new WpfPoint(0, 0));
        var bottomRight = element.PointToScreen(new WpfPoint(element.ActualWidth, element.ActualHeight));
        return new WpfRect(
            Math.Min(topLeft.X, bottomRight.X),
            Math.Min(topLeft.Y, bottomRight.Y),
            Math.Abs(bottomRight.X - topLeft.X),
            Math.Abs(bottomRight.Y - topLeft.Y));
    }

    private static void EnsureInside(WpfRect content, WpfRect container, string label)
    {
        if (!BrowserSurfaceGeometry.Contains(ToSurfaceRect(container), ToSurfaceRect(content), BoundsTolerancePixels))
            throw new InvalidOperationException(
                $"{label}: bounds físicos extrapolam BrowserWindow ({content.Left:0.#},{content.Top:0.#},{content.Right:0.#},{content.Bottom:0.#}).");
    }

    private static DrawingColor SampleScreenPixel(int x, int y)
    {
        using var bitmap = new Bitmap(1, 1, System.Drawing.Imaging.PixelFormat.Format32bppArgb);
        using (var graphics = Graphics.FromImage(bitmap))
            graphics.CopyFromScreen(x, y, 0, 0, new System.Drawing.Size(1, 1), CopyPixelOperation.SourceCopy);
        return bitmap.GetPixel(0, 0);
    }

    private static BrowserSurfaceRect ToSurfaceRect(WpfRect rect) => rect.IsEmpty
        ? new BrowserSurfaceRect(0, 0, 0, 0)
        : new BrowserSurfaceRect(rect.X, rect.Y, rect.Width, rect.Height);

    private static RectReport ToReport(WpfRect rect) => rect.IsEmpty
        ? new RectReport(0, 0, 0, 0)
        : new RectReport(Math.Round(rect.X, 2), Math.Round(rect.Y, 2), Math.Round(rect.Width, 2), Math.Round(rect.Height, 2));

    private static RectReport ToReport(BrowserSurfaceRect rect) => new(
        Math.Round(rect.X, 2), Math.Round(rect.Y, 2), Math.Round(rect.Width, 2), Math.Round(rect.Height, 2));

    private const string SentinelHtml = """
        <!doctype html>
        <html>
        <head>
          <meta charset="utf-8">
          <meta name="color-scheme" content="dark">
          <title>CloudOS Surface Sentinel</title>
          <style>
            html,body{margin:0;width:100%;height:100%;overflow:hidden;background:#19324a}
            #cloudos-surface-physical-probe{position:fixed;inset:0;z-index:2147483646;background:#19324a}
            #cloudos-surface-label{position:fixed;left:12px;top:12px;z-index:2147483647;color:#f3f5f7;font:600 16px Segoe UI,sans-serif}
          </style>
        </head>
        <body>
          <div id="cloudos-surface-physical-probe" data-cloudos-sentinel="v2"></div>
          <div id="cloudos-surface-label">CloudOS WebView · conteúdo preservado</div>
        </body>
        </html>
        """;

    [DllImport("dwmapi.dll")]
    private static extern int DwmFlush();

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetWindowRect(IntPtr hwnd, out RectNative rect);

    [StructLayout(LayoutKind.Sequential)]
    private struct RectNative
    {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }

    private sealed class SentinelState
    {
        internal bool NavigationCompleted { get; set; }
        internal bool DocumentConfirmed { get; set; }
        internal string? LastObservedSurface { get; set; }
        internal string? PendingSurface { get; set; }
    }

    private sealed class ObservationHook
    {
        private readonly Window _window;
        private readonly Border _hub;
        private readonly TextBlock _title;
        private readonly WebView2 _webView;
        private readonly SentinelState _state;

        internal ObservationHook(Window window, Border hub, TextBlock title, WebView2 webView, SentinelState state)
        {
            _window = window;
            _hub = hub;
            _title = title;
            _webView = webView;
            _state = state;
        }

        internal void OnLayoutUpdated(object? sender, EventArgs e)
        {
            if (_hub.Visibility != Visibility.Visible || _webView.CoreWebView2 is null) return;
            var surface = _title.Text switch
            {
                "Downloads" => "downloads",
                "Extensões" => "extensions",
                "Configurações" => "settings",
                _ => null
            };
            if (surface is null || string.Equals(_state.LastObservedSurface, surface, StringComparison.Ordinal) ||
                string.Equals(_state.PendingSurface, surface, StringComparison.Ordinal))
                return;

            _state.PendingSurface = surface;
            _ = ObserveAsync(surface);
        }

        private async Task ObserveAsync(string surface)
        {
            try
            {
                await _window.Dispatcher.InvokeAsync(() => _window.UpdateLayout(), System.Windows.Threading.DispatcherPriority.Render);
                await Task.Delay(90);
                if (_hub.Visibility != Visibility.Visible || _webView.CoreWebView2 is null) return;
                _state.DocumentConfirmed = await ConfirmSentinelDocumentAsync(_webView.CoreWebView2);
                _state.LastObservedSurface = _state.DocumentConfirmed ? surface : null;
                _window.UpdateLayout();
                _ = DwmFlush();
                var preliminary = MeasureHubAndWebView(_window, _hub, _webView, surface, _state);
                ProbeRunReport.Current?.RegisterSurface(surface, preliminary, finalMeasurement: false);
                TryCaptureStageArtifact(_window, surface);
            }
            catch (Exception error) when (error is InvalidOperationException or COMException or DllNotFoundException)
            {
                _state.DocumentConfirmed = false;
                _state.LastObservedSurface = null;
                ProbeRunReport.Current?.RegisterSurface(surface, new SurfaceVisualReport
                {
                    Stage = surface,
                    NavigationCompleted = _state.NavigationCompleted,
                    DocumentConfirmed = false,
                    ExpectedColor = new RgbReport(SentinelColor.R, SentinelColor.G, SentinelColor.B),
                    FailureClassification = error is DllNotFoundException ? "capture-unavailable" : "sentinel-navigation-not-completed",
                    FailureDetail = error is DllNotFoundException ? "DWM/captura indisponível." : "Documento sentinela não pôde ser reconfirmado após o hub."
                }, finalMeasurement: false);
                TryCaptureStageArtifact(_window, surface);
            }
            finally
            {
                _state.PendingSurface = null;
            }
        }

        internal void OnWindowClosed(object? sender, EventArgs e)
        {
            _hub.LayoutUpdated -= OnLayoutUpdated;
            _window.Closed -= OnWindowClosed;
        }
    }
}
