using System.Drawing;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Text.Json;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using CloudOS.Host.Browser;
using Microsoft.Web.WebView2.Core;

namespace CloudOS.Browser.PhysicalProbe;

internal static class Program
{
    private const string ShortInput = "youtube.com";
    private const string PasteInput = "paste-validation.example/path";
    private const string LongInput = "https://www.youtube.com/results?search_query=cloudos+browser+physical+validation+long+address+bar+input&sp=EgIQAQ%253D%253D";
    private static int _exitCode;

    [STAThread]
    private static int Main(string[] args)
    {
        var options = ProbeOptions.Parse(args);
        var app = new Application { ShutdownMode = ShutdownMode.OnExplicitShutdown };
        app.Startup += (_, _) => app.Dispatcher.BeginInvoke(new Action(async () =>
        {
            try { await RunAsync(options); _exitCode = 0; }
            catch (ProbeFailure error) { Console.Error.WriteLine(error.Message); _exitCode = 2; }
            catch (Exception error) { Console.Error.WriteLine($"UNEXPECTED: {error}"); _exitCode = 3; }
            finally { app.Shutdown(_exitCode); }
        }), DispatcherPriority.ApplicationIdle);
        app.Run();
        return _exitCode;
    }

    private static async Task RunAsync(ProbeOptions options)
    {
        Directory.CreateDirectory(options.OutputDirectory);
        var tempRoot = Path.Combine(Path.GetTempPath(), "CloudOS", "BrowserPhysicalProbe", Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(tempRoot);
        BrowserWindow? window = null;
        try
        {
            var environmentOptions = new CoreWebView2EnvironmentOptions { AreBrowserExtensionsEnabled = true };
            var environment = await CoreWebView2Environment.CreateAsync(null, Path.Combine(tempRoot, "WebView2"), environmentOptions);
            var policy = new BrowserPolicy(new Uri("https://cloudos.local/"), new Uri("http://127.0.0.1:65530/"));
            var state = new BrowserStateStore(Path.Combine(tempRoot, "browser-state.json"));
            window = new BrowserWindow(environment, policy, state, developerMode: false)
            {
                Width = 1280, Height = 800, Left = 80, Top = 60,
                WindowStartupLocation = WindowStartupLocation.Manual
            };
            window.Show();
            window.Activate();
            await window.Dispatcher.InvokeAsync(() => { }, DispatcherPriority.Loaded);
            SetTheme(window, options.Theme);
            await window.InitializeAsync(null);
            await PumpAsync(450);

            var scale = VisualTreeHelper.GetDpi(window).DpiScaleX * 100d;
            if (options.ExpectedScale is not null && Math.Abs(scale - options.ExpectedScale.Value) > 2.5d)
                throw new ProbeFailure($"DPI_SCALE_MISMATCH: esperado {options.ExpectedScale:0}% e o Windows reportou {scale:0.##}%.");

            var address = Require<TextBox>(window, "AddressBox");
            var shell = Require<Border>(window, "AddressShell");
            var placeholder = Require<TextBlock>(window, "AddressPlaceholder");
            Assert(address.Foreground is not null, "AddressBox.Foreground ausente.");
            Assert(address.CaretBrush is not null, "AddressBox.CaretBrush ausente.");
            Assert(address.SelectionBrush is not null, "AddressBox.SelectionBrush ausente.");
            Assert(address.VerticalContentAlignment == VerticalAlignment.Center, "AddressBox não está centralizado verticalmente.");
            Assert(address.ActualHeight >= 30, $"AddressBox muito baixo: {address.ActualHeight:0.##}.");
            Assert(shell.ActualWidth >= 320, $"Omnibox estreita em janela normal: {shell.ActualWidth:0.##}.");

            address.Clear();
            Focus(window, address);
            await PumpAsync(80);
            Assert(placeholder.Visibility != Visibility.Visible, "Placeholder deve desaparecer durante edição.");

            SendText(ShortInput);
            await PumpAsync(100);
            Assert(address.Text == ShortInput, $"Digitação curta divergente: '{address.Text}'.");
            AssertVerticalBounds(address, "youtube.com");
            Capture(window, options, "01-youtube-typed.png");

            Chord(VK_CONTROL, 'A'); await PumpAsync(60);
            Assert(address.SelectionLength == address.Text.Length, "Ctrl+A não selecionou tudo.");
            Capture(window, options, "02-youtube-selected.png");

            Chord(VK_CONTROL, 'C'); await PumpAsync(60);
            Assert(Clipboard.ContainsText() && Clipboard.GetText() == ShortInput, "Ctrl+C falhou.");
            Clipboard.SetText(PasteInput);
            Chord(VK_CONTROL, 'A'); Chord(VK_CONTROL, 'V'); await PumpAsync(80);
            Assert(address.Text == PasteInput, "Ctrl+V falhou.");
            AssertVerticalBounds(address, "paste");
            Capture(window, options, "03-paste.png");

            Chord(VK_CONTROL, 'A'); SendText(LongInput); await PumpAsync(100);
            Assert(address.Text == LongInput, "URL longa foi truncada ou alterada.");
            AssertVerticalBounds(address, "long-url");
            Key(VK_HOME); await PumpAsync(50);
            Assert(address.CaretIndex == 0, $"Home falhou: {address.CaretIndex}.");
            Capture(window, options, "04-long-url-home.png");
            Key(VK_END); await PumpAsync(50);
            Assert(address.CaretIndex == address.Text.Length, $"End falhou: {address.CaretIndex}/{address.Text.Length}.");
            AssertVerticalBounds(address, "long-url-end");
            Capture(window, options, "05-long-url-end.png");

            if (!options.NoNavigation)
            {
                Chord(VK_CONTROL, 'A'); SendText(ShortInput); Key(VK_RETURN);
                await PumpAsync(2300);
                Capture(window, options, "06-after-navigation.png");
            }

            window.Width = 820; window.Height = 620; await PumpAsync(180);
            Assert(shell.ActualWidth >= 250, $"Omnibox estreita demais no modo compacto: {shell.ActualWidth:0.##}.");
            Capture(window, options, "07-compact.png");

            window.Width = 1280; window.Height = 800; SetTheme(window, BrowserThemeMode.Dark); await PumpAsync(130);
            Capture(window, options, "08-dark-normal.png");
            window.Width = 820; window.Height = 620; await PumpAsync(130); Capture(window, options, "09-dark-compact.png");
            window.Width = 1280; window.Height = 800; SetTheme(window, BrowserThemeMode.Light); await PumpAsync(130);
            Capture(window, options, "10-light-normal.png");
            window.Width = 820; window.Height = 620; await PumpAsync(130); Capture(window, options, "11-light-compact.png");

            var report = new
            {
                passed = true,
                physicalScreenCapture = options.ScreenCapture,
                reportedScalePercent = Math.Round(scale, 2),
                expectedScalePercent = options.ExpectedScale,
                shortInput = ShortInput,
                longInputLength = LongInput.Length,
                checks = new[] { "typing", "ctrl+a", "ctrl+c", "ctrl+v", "home", "end", "vertical-bounds", "normal-width", "compact-width", "dark", "light" }
            };
            await File.WriteAllTextAsync(Path.Combine(options.OutputDirectory, "validation.json"), JsonSerializer.Serialize(report, new JsonSerializerOptions { WriteIndented = true }));
            Console.WriteLine($"PASS Browser physical UI probe | scale={scale:0.##}% | screen={options.ScreenCapture}");
        }
        finally
        {
            try { if (window is { IsVisible: true }) window.CloseForHostShutdown(); } catch { }
            await Dispatcher.CurrentDispatcher.InvokeAsync(() => { }, DispatcherPriority.ApplicationIdle);
            try { if (Directory.Exists(tempRoot)) Directory.Delete(tempRoot, true); } catch { }
        }
    }

    private static T Require<T>(FrameworkElement root, string name) where T : class =>
        root.FindName(name) as T ?? throw new ProbeFailure($"Elemento WPF ausente: {name}.");

    private static void SetTheme(BrowserWindow window, BrowserThemeMode mode)
    {
        var method = typeof(BrowserWindow).GetMethod("SetChromeTheme", BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic)
            ?? throw new ProbeFailure("SetChromeTheme não encontrado.");
        method.Invoke(window, [mode]);
    }

    private static void Focus(Window window, TextBox box)
    {
        window.Activate(); box.Focus(); System.Windows.Input.Keyboard.Focus(box);
        var hwnd = new WindowInteropHelper(window).Handle;
        if (hwnd != IntPtr.Zero) SetForegroundWindow(hwnd);
    }

    private static void AssertVerticalBounds(TextBox box, string stage)
    {
        if (box.Text.Length == 0) return;
        var first = box.GetRectFromCharacterIndex(0, false);
        var last = box.GetRectFromCharacterIndex(box.Text.Length - 1, true);
        Assert(!first.IsEmpty && !last.IsEmpty, $"{stage}: bounds de texto ausentes.");
        var top = Math.Min(first.Top, last.Top);
        var bottom = Math.Max(first.Bottom, last.Bottom);
        Assert(top >= -1.5, $"{stage}: texto cortado no topo ({top:0.##}).");
        Assert(bottom <= box.ActualHeight + 1.5, $"{stage}: texto cortado embaixo ({bottom:0.##}/{box.ActualHeight:0.##}).");
        Assert(first.Height > 4 && first.Height <= box.ActualHeight, $"{stage}: altura de glyph inválida ({first.Height:0.##}).");
    }

    private static async Task PumpAsync(int milliseconds)
    {
        var until = Environment.TickCount64 + milliseconds;
        while (Environment.TickCount64 < until)
        {
            await Dispatcher.CurrentDispatcher.InvokeAsync(() => { }, DispatcherPriority.Background);
            await Task.Delay(15);
        }
    }

    private static void Capture(Window window, ProbeOptions options, string name)
    {
        var path = Path.Combine(options.OutputDirectory, name);
        if (options.ScreenCapture) CaptureScreen(window, path); else CaptureWpf(window, path);
    }

    private static void CaptureWpf(Window window, string path)
    {
        window.UpdateLayout();
        var source = PresentationSource.FromVisual(window);
        var transform = source?.CompositionTarget?.TransformToDevice ?? Matrix.Identity;
        var width = Math.Max(1, (int)Math.Round(window.ActualWidth * transform.M11));
        var height = Math.Max(1, (int)Math.Round(window.ActualHeight * transform.M22));
        var bitmap = new RenderTargetBitmap(width, height, 96d * transform.M11, 96d * transform.M22, PixelFormats.Pbgra32);
        bitmap.Render(window);
        using var stream = File.Create(path);
        var encoder = new PngBitmapEncoder(); encoder.Frames.Add(BitmapFrame.Create(bitmap)); encoder.Save(stream);
    }

    private static void CaptureScreen(Window window, string path)
    {
        var hwnd = new WindowInteropHelper(window).Handle;
        if (hwnd == IntPtr.Zero || !GetWindowRect(hwnd, out var rect)) throw new ProbeFailure("Falha ao obter retângulo físico da janela.");
        SetForegroundWindow(hwnd); Thread.Sleep(100);
        var width = Math.Max(1, rect.Right - rect.Left); var height = Math.Max(1, rect.Bottom - rect.Top);
        using var bitmap = new Bitmap(width, height, System.Drawing.Imaging.PixelFormat.Format32bppArgb);
        using (var graphics = Graphics.FromImage(bitmap)) graphics.CopyFromScreen(rect.Left, rect.Top, 0, 0, new System.Drawing.Size(width, height), CopyPixelOperation.SourceCopy);
        bitmap.Save(path, System.Drawing.Imaging.ImageFormat.Png);
    }

    private static void SendText(string text)
    {
        foreach (var ch in text)
        {
            var inputs = new[] { Input.Unicode(ch, false), Input.Unicode(ch, true) };
            if (SendInput((uint)inputs.Length, inputs, Marshal.SizeOf<Input>()) != (uint)inputs.Length) throw new ProbeFailure("SendInput Unicode falhou.");
        }
    }

    private static void Chord(ushort modifier, char key)
    {
        Key(modifier, false); Key((ushort)char.ToUpperInvariant(key), false); Key((ushort)char.ToUpperInvariant(key), true); Key(modifier, true);
    }

    private static void Key(ushort key, bool up = false)
    {
        var input = Input.VirtualKey(key, up);
        if (SendInput(1, [input], Marshal.SizeOf<Input>()) != 1) throw new ProbeFailure($"SendInput falhou para VK 0x{key:X2}.");
    }

    private static void Assert(bool condition, string message) { if (!condition) throw new ProbeFailure(message); }

    private const ushort VK_CONTROL = 0x11, VK_HOME = 0x24, VK_END = 0x23, VK_RETURN = 0x0D;
    private const uint INPUT_KEYBOARD = 1, KEYEVENTF_KEYUP = 0x0002, KEYEVENTF_UNICODE = 0x0004;
    [DllImport("user32.dll", SetLastError = true)] private static extern uint SendInput(uint count, Input[] inputs, int size);
    [DllImport("user32.dll")] [return: MarshalAs(UnmanagedType.Bool)] private static extern bool SetForegroundWindow(IntPtr hwnd);
    [DllImport("user32.dll")] [return: MarshalAs(UnmanagedType.Bool)] private static extern bool GetWindowRect(IntPtr hwnd, out RectNative rect);

    [StructLayout(LayoutKind.Sequential)] private struct Input
    {
        public uint type; public InputUnion union;
        public static Input Unicode(char c, bool up) => new() { type = INPUT_KEYBOARD, union = new InputUnion { keyboard = new KeyboardInput { scanCode = c, flags = KEYEVENTF_UNICODE | (up ? KEYEVENTF_KEYUP : 0) } } };
        public static Input VirtualKey(ushort key, bool up) => new() { type = INPUT_KEYBOARD, union = new InputUnion { keyboard = new KeyboardInput { virtualKey = key, flags = up ? KEYEVENTF_KEYUP : 0 } } };
    }
    [StructLayout(LayoutKind.Explicit)] private struct InputUnion { [FieldOffset(0)] public KeyboardInput keyboard; }
    [StructLayout(LayoutKind.Sequential)] private struct KeyboardInput { public ushort virtualKey; public ushort scanCode; public uint flags; public uint time; public UIntPtr extraInfo; }
    [StructLayout(LayoutKind.Sequential)] private struct RectNative { public int Left, Top, Right, Bottom; }
    private sealed class ProbeFailure(string message) : Exception(message);

    private sealed record ProbeOptions(string OutputDirectory, double? ExpectedScale, BrowserThemeMode Theme, bool ScreenCapture, bool NoNavigation)
    {
        public static ProbeOptions Parse(string[] args)
        {
            var output = Path.GetFullPath(Path.Combine(Environment.CurrentDirectory, "test-results", "native-browser-physical-ui"));
            double? expected = null; var theme = BrowserThemeMode.Dark; var screen = false; var noNavigation = false;
            for (var i = 0; i < args.Length; i++)
            {
                switch (args[i])
                {
                    case "--output" when i + 1 < args.Length: output = Path.GetFullPath(args[++i]); break;
                    case "--expected-scale" when i + 1 < args.Length: expected = double.Parse(args[++i], System.Globalization.CultureInfo.InvariantCulture); break;
                    case "--theme" when i + 1 < args.Length: theme = args[++i].ToLowerInvariant() switch { "light" => BrowserThemeMode.Light, "system" => BrowserThemeMode.System, _ => BrowserThemeMode.Dark }; break;
                    case "--screen": screen = true; break;
                    case "--no-navigation": noNavigation = true; break;
                }
            }
            return new ProbeOptions(output, expected, theme, screen, noNavigation);
        }
    }
}
