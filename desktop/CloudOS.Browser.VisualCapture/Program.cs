using System.Reflection;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using CloudOS.Host.Browser;
using Microsoft.Web.WebView2.Core;

namespace CloudOS.Browser.VisualCapture;

internal static class Program
{
    [STAThread]
    private static int Main(string[] args)
    {
        if (args.Length == 0)
        {
            Console.Error.WriteLine("Usage: capture <output.png> <legacy|system|light|dark> <width> <height> | compare <left.png> <right.png> <minRatio> <diff.png>");
            return 2;
        }

        if (string.Equals(args[0], "compare", StringComparison.OrdinalIgnoreCase))
            return Compare(args);

        if (!string.Equals(args[0], "capture", StringComparison.OrdinalIgnoreCase) || args.Length != 5)
        {
            Console.Error.WriteLine("Invalid visual capture arguments.");
            return 2;
        }

        var app = new Application { ShutdownMode = ShutdownMode.OnExplicitShutdown };
        app.Resources["CloudOsBackground"] = new SolidColorBrush(Color.FromRgb(11, 18, 32));
        app.Startup += (_, _) =>
        {
            app.Dispatcher.BeginInvoke(new Action(async () =>
            {
                var exitCode = 0;
                try
                {
                    await CaptureAsync(args[1], args[2], ParseDimension(args[3]), ParseDimension(args[4]));
                }
                catch (Exception error)
                {
                    Console.Error.WriteLine($"VISUAL_CAPTURE_FAILED {error.GetType().Name}: {error.Message}");
                    exitCode = 1;
                }
                finally
                {
                    app.Shutdown(exitCode);
                }
            }), DispatcherPriority.ApplicationIdle);
        };
        return app.Run();
    }

    private static int ParseDimension(string value)
    {
        if (!int.TryParse(value, out var parsed) || parsed < 600 || parsed > 3840)
            throw new ArgumentOutOfRangeException(nameof(value), "Capture dimensions must be between 600 and 3840 pixels.");
        return parsed;
    }

    private static async Task CaptureAsync(string outputPath, string theme, int width, int height)
    {
        var root = Path.Combine(Path.GetTempPath(), $"cloudos-browser-visual-{Guid.NewGuid():N}");
        var udf = Path.Combine(root, "WebView2");
        var statePath = Path.Combine(root, "browser-state.json");
        Directory.CreateDirectory(root);

        BrowserWindow? window = null;
        try
        {
            var environment = await CoreWebView2Environment.CreateAsync(null, udf);
            var policy = new BrowserPolicy(
                new Uri("https://cloudos.local/"),
                new Uri("http://127.0.0.1:5173/"));
            var store = new BrowserStateStore(statePath);

            window = new BrowserWindow(environment, policy, store, developerMode: false)
            {
                Width = width,
                Height = height,
                Left = 24,
                Top = 24,
                WindowStartupLocation = WindowStartupLocation.Manual,
                ShowInTaskbar = false
            };

            window.Show();
            await window.Dispatcher.InvokeAsync(() => { }, DispatcherPriority.Loaded);
            ApplyTheme(window, theme);
            await window.InitializeAsync();
            await window.Dispatcher.InvokeAsync(() => window.UpdateLayout(), DispatcherPriority.ApplicationIdle);

            CaptureWindow(window, outputPath);
            Console.WriteLine($"CAPTURED {Path.GetFileName(outputPath)} {window.ActualWidth:0}x{window.ActualHeight:0} theme={theme}");
        }
        finally
        {
            if (window is { IsVisible: true }) window.CloseForHostShutdown();
            await Dispatcher.CurrentDispatcher.InvokeAsync(() => { }, DispatcherPriority.ApplicationIdle);
            TryDelete(root);
        }
    }

    private static void ApplyTheme(BrowserWindow window, string theme)
    {
        if (string.Equals(theme, "legacy", StringComparison.OrdinalIgnoreCase)) return;

        var method = typeof(BrowserWindow).GetMethod(
            "SetChromeTheme",
            BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic);
        if (method is null)
            throw new InvalidOperationException("Current BrowserWindow does not expose the visual theme hook.");

        var parameterType = method.GetParameters().Single().ParameterType;
        var value = Enum.Parse(parameterType, theme, ignoreCase: true);
        method.Invoke(window, [value]);
    }

    private static void CaptureWindow(Window window, string outputPath)
    {
        var source = PresentationSource.FromVisual(window);
        var transform = source?.CompositionTarget?.TransformToDevice ?? Matrix.Identity;
        var pixelWidth = Math.Max(1, (int)Math.Round(window.ActualWidth * transform.M11));
        var pixelHeight = Math.Max(1, (int)Math.Round(window.ActualHeight * transform.M22));
        var dpiX = 96d * transform.M11;
        var dpiY = 96d * transform.M22;

        var bitmap = new RenderTargetBitmap(pixelWidth, pixelHeight, dpiX, dpiY, PixelFormats.Pbgra32);
        bitmap.Render(window);

        Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(outputPath))!);
        using var stream = File.Create(outputPath);
        var encoder = new PngBitmapEncoder();
        encoder.Frames.Add(BitmapFrame.Create(bitmap));
        encoder.Save(stream);
    }

    private static int Compare(string[] args)
    {
        if (args.Length != 5 || !double.TryParse(args[3], System.Globalization.NumberStyles.Float,
                System.Globalization.CultureInfo.InvariantCulture, out var minimumRatio))
        {
            Console.Error.WriteLine("Usage: compare <left.png> <right.png> <minRatio> <diff.png>");
            return 2;
        }

        var left = LoadBgra32(args[1]);
        var right = LoadBgra32(args[2]);
        if (left.PixelWidth != right.PixelWidth || left.PixelHeight != right.PixelHeight)
        {
            Console.Error.WriteLine($"VISUAL_SIZE_MISMATCH left={left.PixelWidth}x{left.PixelHeight} right={right.PixelWidth}x{right.PixelHeight}");
            return 1;
        }

        var stride = left.PixelWidth * 4;
        var leftPixels = new byte[stride * left.PixelHeight];
        var rightPixels = new byte[stride * right.PixelHeight];
        left.CopyPixels(leftPixels, stride, 0);
        right.CopyPixels(rightPixels, stride, 0);
        var diffPixels = new byte[leftPixels.Length];
        long changed = 0;

        for (var offset = 0; offset < leftPixels.Length; offset += 4)
        {
            var different = Math.Abs(leftPixels[offset] - rightPixels[offset]) > 12 ||
                            Math.Abs(leftPixels[offset + 1] - rightPixels[offset + 1]) > 12 ||
                            Math.Abs(leftPixels[offset + 2] - rightPixels[offset + 2]) > 12;
            if (different)
            {
                changed++;
                diffPixels[offset] = 190;
                diffPixels[offset + 1] = 45;
                diffPixels[offset + 2] = 245;
                diffPixels[offset + 3] = 255;
            }
            else
            {
                var gray = (byte)((leftPixels[offset] + leftPixels[offset + 1] + leftPixels[offset + 2]) / 6);
                diffPixels[offset] = gray;
                diffPixels[offset + 1] = gray;
                diffPixels[offset + 2] = gray;
                diffPixels[offset + 3] = 255;
            }
        }

        var total = (long)left.PixelWidth * left.PixelHeight;
        var ratio = total == 0 ? 0 : changed / (double)total;
        SaveBgra32(diffPixels, left.PixelWidth, left.PixelHeight, stride, args[4]);
        Console.WriteLine($"VISUAL_DIFF changed={changed} total={total} ratio={ratio:0.000000} minimum={minimumRatio:0.000000}");

        if (ratio < minimumRatio)
        {
            Console.Error.WriteLine("VISUAL_DIFF_TOO_SMALL: expected a material reviewed visual change.");
            return 1;
        }
        return 0;
    }

    private static BitmapSource LoadBgra32(string path)
    {
        using var stream = File.OpenRead(path);
        var decoder = new PngBitmapDecoder(stream, BitmapCreateOptions.PreservePixelFormat, BitmapCacheOption.OnLoad);
        var converted = new FormatConvertedBitmap(decoder.Frames[0], PixelFormats.Bgra32, null, 0);
        converted.Freeze();
        return converted;
    }

    private static void SaveBgra32(byte[] pixels, int width, int height, int stride, string path)
    {
        var bitmap = BitmapSource.Create(width, height, 96, 96, PixelFormats.Bgra32, null, pixels, stride);
        Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(path))!);
        using var stream = File.Create(path);
        var encoder = new PngBitmapEncoder();
        encoder.Frames.Add(BitmapFrame.Create(bitmap));
        encoder.Save(stream);
    }

    private static void TryDelete(string path)
    {
        try
        {
            if (Directory.Exists(path)) Directory.Delete(path, recursive: true);
        }
        catch (IOException)
        {
        }
        catch (UnauthorizedAccessException)
        {
        }
    }
}
