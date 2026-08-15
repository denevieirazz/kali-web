using System.Drawing;
using System.Text.Json;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.Wpf;
using DrawingColor = System.Drawing.Color;

namespace CloudOS.Browser.PhysicalProbe;

internal static class SurfaceVisualDiagnostics
{
    internal const double BoundsTolerancePixels = 1.5;
    private static readonly DrawingColor SentinelColor = DrawingColor.FromArgb(25, 50, 74);

    internal static SurfaceVisualReport EnsureMenuInsideWindow(Window window, FrameworkElement popupRoot)
    {
        window.UpdateLayout();
        popupRoot.UpdateLayout();
        var windowBounds = ScreenBounds(window);
        var popupBounds = ScreenBounds(popupRoot);
        EnsureInside(popupBounds, windowBounds, "menu-popup");
        return new SurfaceVisualReport(
            "menu",
            ToReport(windowBounds),
            ToReport(popupBounds),
            null,
            null,
            false,
            false,
            null);
    }

    internal static async Task PrepareWebViewSentinelAsync(WebView2 webView)
    {
        if (webView.CoreWebView2 is null)
            throw new InvalidOperationException("WebView2 não inicializado para diagnóstico visual.");

        const string script = """
            (() => {
              const id = 'cloudos-surface-physical-probe';
              let node = document.getElementById(id);
              if (!node) {
                node = document.createElement('div');
                node.id = id;
                document.documentElement.appendChild(node);
              }
              node.setAttribute('style', 'position:fixed;inset:0;z-index:2147483647;background:#19324a;color:#f3f5f7;display:flex;align-items:center;justify-content:center;font:600 24px Segoe UI,sans-serif;letter-spacing:.2px;');
              node.textContent = 'CloudOS WebView · conteúdo preservado';
              return node.id;
            })();
            """;
        var result = await webView.CoreWebView2.ExecuteScriptAsync(script);
        if (!result.Contains("cloudos-surface-physical-probe", StringComparison.Ordinal))
            throw new InvalidOperationException("Sentinela WebView2 não foi instalada.");
    }

    internal static async Task<CoreWebView2BrowserExtension> AddUnmanagedProbeExtensionAsync(
        CoreWebView2Profile profile,
        string tempRoot)
    {
        var source = Path.Combine(tempRoot, "unmanaged-webview-extension-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(source);
        await File.WriteAllTextAsync(
            Path.Combine(source, "manifest.json"),
            JsonSerializer.Serialize(new
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

        if (hub.Visibility != Visibility.Visible || !hub.IsVisible || hub.ActualWidth < 300 || hub.ActualHeight < 240)
            throw new InvalidOperationException($"{surfaceName}: painel lateral não possui área visual válida.");
        if (webView.Visibility != Visibility.Visible || !webView.IsVisible || webView.ActualWidth < 300 || webView.ActualHeight < 240)
            throw new InvalidOperationException($"{surfaceName}: WebView2 está oculto ou sem área renderizável.");

        var windowBounds = ScreenBounds(window);
        var hubBounds = ScreenBounds(hub);
        var webBounds = ScreenBounds(webView);
        EnsureInside(hubBounds, windowBounds, surfaceName + ":hub");
        EnsureInside(webBounds, windowBounds, surfaceName + ":webview");
        if (webBounds.Right > hubBounds.Left + BoundsTolerancePixels)
            throw new InvalidOperationException($"{surfaceName}: WebView2 invade/é coberto pelo painel lateral.");

        var sampleX = (int)Math.Round(webBounds.Left + webBounds.Width * 0.5);
        var sampleY = (int)Math.Round(webBounds.Top + webBounds.Height * 0.5);
        var sampled = SampleScreenPixel(sampleX, sampleY);
        var white = sampled.R >= 245 && sampled.G >= 245 && sampled.B >= 245;
        var sentinelDistance = Math.Abs(sampled.R - SentinelColor.R) +
                               Math.Abs(sampled.G - SentinelColor.G) +
                               Math.Abs(sampled.B - SentinelColor.B);
        if (white)
            throw new InvalidOperationException($"{surfaceName}: WebView2 apresenta superfície branca física sem estado explícito.");
        if (sentinelDistance > 45)
            throw new InvalidOperationException(
                $"{surfaceName}: sentinela WebView2 não é visível fisicamente (rgb={sampled.R},{sampled.G},{sampled.B}).");

        return new SurfaceVisualReport(
            surfaceName,
            ToReport(windowBounds),
            ToReport(hubBounds),
            ToReport(webBounds),
            new RgbReport(sampled.R, sampled.G, sampled.B),
            true,
            false,
            Math.Round(hubBounds.Left - webBounds.Right, 2));
    }

    internal static void EnsureElementVisibleInScrollViewer(ScrollViewer scroll, FrameworkElement element, string label)
    {
        scroll.UpdateLayout();
        element.UpdateLayout();
        var elementBounds = element.TransformToAncestor(scroll).TransformBounds(new Rect(0, 0, element.ActualWidth, element.ActualHeight));
        var viewport = new Rect(0, 0, scroll.ViewportWidth, scroll.ViewportHeight);
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

    private static System.Windows.Rect ScreenBounds(FrameworkElement element)
    {
        var topLeft = element.PointToScreen(new System.Windows.Point(0, 0));
        var bottomRight = element.PointToScreen(new System.Windows.Point(element.ActualWidth, element.ActualHeight));
        return new System.Windows.Rect(
            Math.Min(topLeft.X, bottomRight.X),
            Math.Min(topLeft.Y, bottomRight.Y),
            Math.Abs(bottomRight.X - topLeft.X),
            Math.Abs(bottomRight.Y - topLeft.Y));
    }

    private static void EnsureInside(System.Windows.Rect content, System.Windows.Rect container, string label)
    {
        if (content.Left < container.Left - BoundsTolerancePixels ||
            content.Top < container.Top - BoundsTolerancePixels ||
            content.Right > container.Right + BoundsTolerancePixels ||
            content.Bottom > container.Bottom + BoundsTolerancePixels)
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

    private static RectReport ToReport(System.Windows.Rect rect) => new(
        Math.Round(rect.X, 2),
        Math.Round(rect.Y, 2),
        Math.Round(rect.Width, 2),
        Math.Round(rect.Height, 2));
}
