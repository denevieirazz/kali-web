using System.Drawing;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Text.Json;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
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
    private const int InputSizeX64 = 40;
    private const int InputSizeX86 = 28;
    private static int _exitCode;
    private static ProbeRunReport? _report;

    [STAThread]
    private static int Main(string[] args)
    {
        var options = ProbeOptions.Parse(args);
        if (options.ValidateInputLayoutOnly)
        {
            try
            {
                var layout = ValidateNativeInputLayout();
                Console.WriteLine($"PASS native INPUT layout | arch={layout.Architecture} | INPUT={layout.InputSize} | union={layout.UnionSize}");
                return 0;
            }
            catch (ProbeFailure error)
            {
                Console.Error.WriteLine(error.Message);
                return 2;
            }
            catch (Exception error)
            {
                Console.Error.WriteLine($"UNEXPECTED_{error.GetType().Name}");
                return 3;
            }
        }

        if (options.ValidateDiagnosticsContractOnly)
            return ValidateDiagnosticsContract(options);

        try
        {
            Directory.CreateDirectory(options.OutputDirectory);
            _report = new ProbeRunReport
            {
                Passed = false,
                Mode = "physical",
                PhysicalValidation = true,
                Stage = "startup",
                PhysicalScreenCapture = options.ScreenCapture,
                ExpectedScalePercent = options.ExpectedScale,
                ShortInput = ShortInput,
                LongInputLength = LongInput.Length
            };
        }
        catch (Exception error)
        {
            Console.Error.WriteLine($"REPORT_INIT_FAILED: {error.GetType().Name}");
            return 3;
        }

        var app = new Application { ShutdownMode = ShutdownMode.OnExplicitShutdown };
        app.Startup += (_, _) => app.Dispatcher.BeginInvoke(new Action(async () =>
        {
            try
            {
                await RunAsync(options);
                _exitCode = 0;
            }
            catch (ProbeFailure error)
            {
                ApplyFailure(error);
                await WriteReportSafelyAsync(options.OutputDirectory);
                Console.Error.WriteLine(error.Message);
                _exitCode = 2;
            }
            catch (Exception error)
            {
                ApplyUnexpectedFailure(error);
                await WriteReportSafelyAsync(options.OutputDirectory);
                Console.Error.WriteLine($"UNEXPECTED_{error.GetType().Name}");
                _exitCode = 3;
            }
            finally
            {
                app.Shutdown(_exitCode);
            }
        }), DispatcherPriority.ApplicationIdle);
        app.Run();
        return _exitCode;
    }

    private static int ValidateDiagnosticsContract(ProbeOptions options)
    {
        try
        {
            Directory.CreateDirectory(options.OutputDirectory);
            var layout = ValidateNativeInputLayout();
            var report = new ProbeRunReport
            {
                Passed = false,
                Mode = "diagnostics-contract-only",
                PhysicalValidation = false,
                Stage = "diagnostics-contract-self-test",
                PhysicalScreenCapture = false,
                ExpectedScalePercent = null,
                ShortInput = ShortInput,
                LongInputLength = LongInput.Length,
                NativeInput = ToReport(layout),
                Error = new ProbeErrorReport(
                    "SELF_TEST_FAILURE_REPORT",
                    "Synthetic failure used only to validate failure-report serialization on hosted CI.",
                    null,
                    "non-physical-ci-contract")
            };
            report.Checks.Add("failure-report-serialization");
            report.WriteAsync(options.OutputDirectory).GetAwaiter().GetResult();

            var path = Path.Combine(options.OutputDirectory, "validation.json");
            using var document = JsonDocument.Parse(File.ReadAllText(path));
            var root = document.RootElement;
            Assert(root.GetProperty("passed").ValueKind == JsonValueKind.False, "diagnostics contract deve serializar passed=false.");
            Assert(root.GetProperty("physicalValidation").ValueKind == JsonValueKind.False, "diagnostics contract não pode declarar validação física.");
            Assert(root.GetProperty("stage").GetString() == "diagnostics-contract-self-test", "diagnostics contract perdeu a etapa.");
            Assert(root.GetProperty("error").GetProperty("code").GetString() == "SELF_TEST_FAILURE_REPORT", "diagnostics contract perdeu o código de erro.");
            Assert(root.TryGetProperty("artifacts", out _), "diagnostics contract perdeu a lista de artefatos.");
            Console.WriteLine("PASS physical probe failure-report serialization contract (non-physical CI mode)");
            return 0;
        }
        catch (ProbeFailure error)
        {
            Console.Error.WriteLine(error.Message);
            return 2;
        }
        catch (Exception error)
        {
            Console.Error.WriteLine($"DIAGNOSTICS_CONTRACT_FAILED: {error.GetType().Name}");
            return 3;
        }
    }

    private static async Task RunAsync(ProbeOptions options)
    {
        SetStage("native-input-layout");
        var inputLayout = ValidateNativeInputLayout();
        if (_report is not null) _report.NativeInput = ToReport(inputLayout);

        var tempRoot = Path.Combine(Path.GetTempPath(), "CloudOS", "BrowserPhysicalProbe", Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(tempRoot);
        BrowserWindow? window = null;
        try
        {
            SetStage("browser-environment");
            var environmentOptions = new CoreWebView2EnvironmentOptions { AreBrowserExtensionsEnabled = true };
            var environment = await CoreWebView2Environment.CreateAsync(null, Path.Combine(tempRoot, "WebView2"), environmentOptions);
            var policy = new BrowserPolicy(new Uri("https://cloudos.local/"), new Uri("http://127.0.0.1:65530/"));
            var state = new BrowserStateStore(Path.Combine(tempRoot, "browser-state.json"));
            window = new BrowserWindow(environment, policy, state, developerMode: false)
            {
                Width = 1280,
                Height = 800,
                Left = 80,
                Top = 60,
                WindowStartupLocation = WindowStartupLocation.Manual
            };

            SetStage("browser-window-show");
            window.Show();
            window.Activate();
            await window.Dispatcher.InvokeAsync(() => { }, DispatcherPriority.Loaded);
            SetTheme(window, options.Theme);

            SetStage("browser-webview-initialize");
            await window.InitializeAsync(null);
            await PumpAsync(450);

            var scale = VisualTreeHelper.GetDpi(window).DpiScaleX * 100d;
            if (_report is not null) _report.ReportedScalePercent = Math.Round(scale, 2);
            if (options.ExpectedScale is not null && Math.Abs(scale - options.ExpectedScale.Value) > 2.5d)
                throw new ProbeFailure(
                    $"DPI_SCALE_MISMATCH: esperado {options.ExpectedScale:0}% e o Windows reportou {scale:0.##}%.",
                    "dpi-scale",
                    "DPI_SCALE_MISMATCH",
                    null,
                    "display-scale-mismatch");

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
            SetStage("preflight-physical-input");
            var beforeFocus = PhysicalInputDiagnostics.Capture(window, address, inputLayout.InputSize);
            var focusRequest = PhysicalInputDiagnostics.RequestFocus(window, address);
            await PumpAsync(120);
            var afterFocus = PhysicalInputDiagnostics.Capture(window, address, inputLayout.InputSize);
            var blockers = PhysicalInputDiagnostics.Evaluate(afterFocus);

            for (var attempt = 1; attempt < 3 && blockers.Count > 0; attempt++)
            {
                focusRequest = PhysicalInputDiagnostics.RequestFocus(window, address);
                await PumpAsync(120);
                afterFocus = PhysicalInputDiagnostics.Capture(window, address, inputLayout.InputSize);
                blockers = PhysicalInputDiagnostics.Evaluate(afterFocus);
            }

            if (_report is not null)
                _report.PhysicalInputContext = new PhysicalInputContext(beforeFocus, focusRequest, afterFocus, blockers);

            if (blockers.Count > 0)
            {
                var primary = blockers[0];
                throw new ProbeFailure(
                    $"PHYSICAL_INPUT_CONTEXT_UNSUPPORTED: reason={primary}.",
                    "preflight-physical-input",
                    "PHYSICAL_INPUT_CONTEXT_UNSUPPORTED",
                    RelevantContextError(afterFocus, primary),
                    ClassifyContextBlocker(primary));
            }

            Assert(placeholder.Visibility != Visibility.Visible, "Placeholder deve desaparecer durante edição.");

            SetStage("sendinput-short-text");
            SendText(ShortInput);
            await PumpAsync(100);
            Assert(address.Text == ShortInput, $"Digitação curta divergente: '{address.Text}'.");
            AssertVerticalBounds(address, "youtube.com");
            Capture(window, options, "01-youtube-typed.png");

            SetStage("sendinput-ctrl-a");
            Chord(VK_CONTROL, 'A');
            await PumpAsync(60);
            Assert(address.SelectionLength == address.Text.Length, "Ctrl+A não selecionou tudo.");
            Capture(window, options, "02-youtube-selected.png");

            SetStage("sendinput-clipboard");
            Chord(VK_CONTROL, 'C');
            await PumpAsync(60);
            Assert(Clipboard.ContainsText() && Clipboard.GetText() == ShortInput, "Ctrl+C falhou.");
            Clipboard.SetText(PasteInput);
            Chord(VK_CONTROL, 'A');
            Chord(VK_CONTROL, 'V');
            await PumpAsync(80);
            Assert(address.Text == PasteInput, "Ctrl+V falhou.");
            AssertVerticalBounds(address, "paste");
            Capture(window, options, "03-paste.png");

            SetStage("sendinput-long-url");
            Chord(VK_CONTROL, 'A');
            SendText(LongInput);
            await PumpAsync(100);
            Assert(address.Text == LongInput, "URL longa foi truncada ou alterada.");
            AssertVerticalBounds(address, "long-url");
            PressKey(VK_HOME);
            await PumpAsync(50);
            Assert(address.CaretIndex == 0, $"Home falhou: {address.CaretIndex}.");
            Capture(window, options, "04-long-url-home.png");
            PressKey(VK_END);
            await PumpAsync(50);
            Assert(address.CaretIndex == address.Text.Length, $"End falhou: {address.CaretIndex}/{address.Text.Length}.");
            AssertVerticalBounds(address, "long-url-end");
            Capture(window, options, "05-long-url-end.png");

            if (!options.NoNavigation)
            {
                SetStage("sendinput-enter-navigation");
                Chord(VK_CONTROL, 'A');
                SendText(ShortInput);
                PressKey(VK_RETURN);
                await PumpAsync(2300);
                Assert(address.Text.Contains("youtube.com", StringComparison.OrdinalIgnoreCase),
                    $"Enter não navegou para youtube.com: '{address.Text}'.");
                Capture(window, options, "06-after-navigation.png");
            }

            SetStage("compact-layout");
            window.Width = 820;
            window.Height = 620;
            await PumpAsync(180);
            Assert(shell.ActualWidth >= 250, $"Omnibox estreita demais no modo compacto: {shell.ActualWidth:0.##}.");
            Capture(window, options, "07-compact.png");

            SetStage("theme-layout-evidence");
            window.Width = 1280;
            window.Height = 800;
            SetTheme(window, BrowserThemeMode.Dark);
            await PumpAsync(130);
            Capture(window, options, "08-dark-normal.png");
            window.Width = 820;
            window.Height = 620;
            await PumpAsync(130);
            Capture(window, options, "09-dark-compact.png");
            window.Width = 1280;
            window.Height = 800;
            SetTheme(window, BrowserThemeMode.Light);
            await PumpAsync(130);
            Capture(window, options, "10-light-normal.png");
            window.Width = 820;
            window.Height = 620;
            await PumpAsync(130);
            Capture(window, options, "11-light-compact.png");

            SetStage("browser-surfaces");
            window.Width = 1280;
            window.Height = 800;
            await PumpAsync(130);
            var menuButton = Require<Button>(window, "BrowserMenuButton");
            var menuPopup = Require<Popup>(window, "BrowserMenuPopup");
            var downloadsButton = Require<Button>(window, "DownloadsButton");
            var hubPanel = Require<Border>(window, "HubPanel");
            var hubTitle = Require<TextBlock>(window, "HubTitle");

            Focus(window, menuButton);
            PressKey(VK_SPACE);
            await PumpAsync(100);
            Assert(menuPopup.IsOpen, "Menu principal não abriu por entrada física.");
            Capture(window, options, "12-menu-open.png");
            menuPopup.IsOpen = false;
            await PumpAsync(60);

            Focus(window, downloadsButton);
            PressKey(VK_SPACE);
            await PumpAsync(120);
            Assert(hubPanel.Visibility == Visibility.Visible, "Hub de Downloads não ficou visível.");
            Assert(string.Equals(hubTitle.Text, "Downloads", StringComparison.Ordinal),
                $"Hub de Downloads divergente: '{hubTitle.Text}'.");
            Capture(window, options, "13-downloads-hub.png");

            Focus(window, menuButton);
            PressKey(VK_SPACE);
            await PumpAsync(100);
            Assert(menuPopup.IsOpen, "Menu principal não reabriu para Configurações.");
            var menuRoot = menuPopup.Child ?? throw new ProbeFailure("Conteúdo do menu principal ausente.");
            var settingsButton = RequireButtonByContent(menuRoot, "Configurações");
            Focus(window, settingsButton);
            PressKey(VK_SPACE);
            await PumpAsync(120);
            Assert(hubPanel.Visibility == Visibility.Visible, "Hub de Configurações não ficou visível.");
            Assert(string.Equals(hubTitle.Text, "Configurações", StringComparison.Ordinal),
                $"Hub de Configurações divergente: '{hubTitle.Text}'.");
            Capture(window, options, "14-settings-hub.png");

            if (_report is not null)
            {
                _report.Passed = true;
                _report.Stage = "completed";
                _report.Error = null;
                _report.Checks.AddRange([
                    "native-input-layout",
                    "interactive-input-desktop",
                    "integrity-context",
                    "foreground-window",
                    "thread-input-queue",
                    "wpf-native-focus",
                    "sendinput-unicode",
                    "typing",
                    "ctrl+a",
                    "ctrl+c",
                    "ctrl+v",
                    "home",
                    "end",
                    "enter-navigation",
                    "vertical-bounds",
                    "normal-width",
                    "compact-width",
                    "dark",
                    "light",
                    "menu",
                    "downloads",
                    "settings"
                ]);
                await _report.WriteAsync(options.OutputDirectory);
            }

            Console.WriteLine($"PASS Browser physical UI probe | scale={scale:0.##}% | screen={options.ScreenCapture} | INPUT={inputLayout.InputSize}");
        }
        catch
        {
            TryCaptureFailure(window, options);
            throw;
        }
        finally
        {
            try
            {
                if (window is { IsVisible: true }) window.CloseForHostShutdown();
            }
            catch
            {
            }
            await Dispatcher.CurrentDispatcher.InvokeAsync(() => { }, DispatcherPriority.ApplicationIdle);
            try
            {
                if (Directory.Exists(tempRoot)) Directory.Delete(tempRoot, true);
            }
            catch
            {
            }
        }
    }

    private static NativeInputReport ToReport(NativeInputLayout layout) => new(
        layout.Architecture,
        layout.InputSize,
        layout.UnionSize,
        layout.MouseSize,
        layout.KeyboardSize,
        layout.HardwareSize);

    private static void SetStage(string stage)
    {
        if (_report is not null) _report.Stage = stage;
    }

    private static void ApplyFailure(ProbeFailure error)
    {
        if (_report is null) return;
        _report.Passed = false;
        if (!string.IsNullOrWhiteSpace(error.Stage)) _report.Stage = error.Stage!;
        _report.Error = new ProbeErrorReport(error.Code, error.Message, error.Win32, error.Classification);
    }

    private static void ApplyUnexpectedFailure(Exception error)
    {
        if (_report is null) return;
        _report.Passed = false;
        _report.Error = new ProbeErrorReport(
            "UNEXPECTED_EXCEPTION",
            $"Unexpected probe failure of type {error.GetType().Name}.",
            null,
            "unexpected-managed-failure");
    }

    private static async Task WriteReportSafelyAsync(string outputDirectory)
    {
        if (_report is null) return;
        try
        {
            await _report.WriteAsync(outputDirectory);
        }
        catch (Exception error)
        {
            Console.Error.WriteLine($"REPORT_WRITE_FAILED: {error.GetType().Name}");
        }
    }

    private static string ClassifyContextBlocker(string blocker) => blocker switch
    {
        "non-interactive-process" or "session-zero" or "window-station-not-visible" or "thread-desktop-not-input"
            or "input-desktop-unavailable" or "thread-desktop-differs-from-input-desktop" => "non-interactive-or-wrong-input-desktop",
        "foreground-higher-integrity" => "integrity-level-mismatch-uipi-possible",
        "foreground-not-probe-window" => "foreground-window-mismatch",
        "foreground-input-queue-differs" or "window-thread-mismatch" => "thread-input-queue-mismatch",
        "wpf-window-not-active" or "wpf-focus-mismatch" or "native-active-window-mismatch" or "native-keyboard-focus-mismatch" => "focus-mismatch",
        "process-integrity-unavailable" => "integrity-diagnostics-unavailable",
        "modifier-key-already-down" => "physical-key-state-not-clean",
        _ => "physical-context-unsupported"
    };

    private static int? RelevantContextError(PhysicalInputSnapshot snapshot, string blocker) => blocker switch
    {
        "window-station-not-visible" => snapshot.Desktop.WindowStationFlagsError,
        "thread-desktop-not-input" => snapshot.Desktop.ThreadDesktopIoError,
        "input-desktop-unavailable" => snapshot.Desktop.InputDesktopError,
        "gui-thread-info-unavailable" => snapshot.GuiThreadInfoError,
        "process-integrity-unavailable" => snapshot.ProcessToken.Error,
        _ => null
    };

    private static T Require<T>(FrameworkElement root, string name) where T : class =>
        root.FindName(name) as T ?? throw new ProbeFailure($"Elemento WPF ausente: {name}.");

    private static Button RequireButtonByContent(DependencyObject root, string content)
    {
        var button = FindButtonByContent(root, content);
        return button ?? throw new ProbeFailure($"Botão de menu ausente: {content}.");
    }

    private static Button? FindButtonByContent(DependencyObject root, string content)
    {
        if (root is Button button && string.Equals(button.Content as string, content, StringComparison.Ordinal))
            return button;

        var children = VisualTreeHelper.GetChildrenCount(root);
        for (var i = 0; i < children; i++)
        {
            var found = FindButtonByContent(VisualTreeHelper.GetChild(root, i), content);
            if (found is not null) return found;
        }
        return null;
    }

    private static void SetTheme(BrowserWindow window, BrowserThemeMode mode)
    {
        var method = typeof(BrowserWindow).GetMethod("SetChromeTheme", BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic)
            ?? throw new ProbeFailure("SetChromeTheme não encontrado.");
        method.Invoke(window, [mode]);
    }

    private static void Focus(Window window, FrameworkElement element)
    {
        window.Activate();
        var hwnd = new WindowInteropHelper(window).Handle;
        if (hwnd != IntPtr.Zero) SetForegroundWindow(hwnd);
        element.Focus();
        System.Windows.Input.Keyboard.Focus(element);
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
        if (_report is not null && !_report.Artifacts.Contains(name, StringComparer.Ordinal))
            _report.Artifacts.Add(name);
    }

    private static void TryCaptureFailure(Window? window, ProbeOptions options)
    {
        if (window is not { IsVisible: true }) return;
        const string name = "00-failure-context.png";
        if (_report is not null && _report.Artifacts.Contains(name, StringComparer.Ordinal)) return;
        try
        {
            Capture(window, options, name);
        }
        catch
        {
        }
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
        var encoder = new PngBitmapEncoder();
        encoder.Frames.Add(BitmapFrame.Create(bitmap));
        encoder.Save(stream);
    }

    private static void CaptureScreen(Window window, string path)
    {
        var hwnd = new WindowInteropHelper(window).Handle;
        if (hwnd == IntPtr.Zero || !GetWindowRect(hwnd, out var rect))
            throw new ProbeFailure("Falha ao obter retângulo físico da janela.");
        SetForegroundWindow(hwnd);
        Thread.Sleep(100);
        var width = Math.Max(1, rect.Right - rect.Left);
        var height = Math.Max(1, rect.Bottom - rect.Top);
        using var bitmap = new Bitmap(width, height, System.Drawing.Imaging.PixelFormat.Format32bppArgb);
        using (var graphics = Graphics.FromImage(bitmap))
            graphics.CopyFromScreen(rect.Left, rect.Top, 0, 0, new System.Drawing.Size(width, height), CopyPixelOperation.SourceCopy);
        bitmap.Save(path, System.Drawing.Imaging.ImageFormat.Png);
    }

    private static void SendText(string text)
    {
        foreach (var ch in text)
        {
            var inputs = new[] { Input.Unicode(ch, false), Input.Unicode(ch, true) };
            SendInputs(inputs, $"unicode-U+{(int)ch:X4}");
        }
    }

    private static void Chord(ushort modifier, char key)
    {
        Key(modifier, false);
        Key((ushort)char.ToUpperInvariant(key), false);
        Key((ushort)char.ToUpperInvariant(key), true);
        Key(modifier, true);
    }

    private static void PressKey(ushort key)
    {
        Key(key, false);
        Key(key, true);
    }

    private static void Key(ushort key, bool up)
    {
        SendInputs([Input.VirtualKey(key, up)], $"vk-0x{key:X2}-{(up ? "up" : "down")}");
    }

    private static void SendInputs(Input[] inputs, string operation)
    {
        var inputSize = Marshal.SizeOf<Input>();
        var sent = SendInput((uint)inputs.Length, inputs, inputSize);
        if (sent == (uint)inputs.Length) return;

        var errorCode = Marshal.GetLastPInvokeError();
        var validPreflight = _report?.PhysicalInputContext is { Blockers.Count: 0 };
        var classification = validPreflight
            ? "sendinput-zero-after-valid-interactive-preflight"
            : "sendinput-zero-without-valid-preflight";
        throw new ProbeFailure(
            $"SEND_INPUT_FAILED: operation={operation}; sent={sent}/{inputs.Length}; cbSize={inputSize}; win32={errorCode}.",
            $"sendinput:{operation}",
            "SEND_INPUT_BLOCKED",
            errorCode,
            classification);
    }

    private static NativeInputLayout ValidateNativeInputLayout()
    {
        if (IntPtr.Size is not (4 or 8))
            throw new ProbeFailure($"NATIVE_INPUT_LAYOUT_UNSUPPORTED: pointerSize={IntPtr.Size}.");

        var x64 = IntPtr.Size == 8;
        var architecture = x64 ? "x64" : "x86";
        var expectedInputSize = x64 ? InputSizeX64 : InputSizeX86;
        var expectedUnionSize = x64 ? 32 : 24;
        var expectedMouseSize = x64 ? 32 : 24;
        var expectedKeyboardSize = x64 ? 24 : 16;
        const int expectedHardwareSize = 8;

        var inputSize = Marshal.SizeOf<Input>();
        var unionSize = Marshal.SizeOf<InputUnion>();
        var mouseSize = Marshal.SizeOf<MouseInput>();
        var keyboardSize = Marshal.SizeOf<KeyboardInput>();
        var hardwareSize = Marshal.SizeOf<HardwareInput>();

        Assert(inputSize == expectedInputSize,
            $"NATIVE_INPUT_LAYOUT_INVALID: arch={architecture}; INPUT={inputSize}; expected={expectedInputSize}.");
        Assert(unionSize == expectedUnionSize,
            $"NATIVE_INPUT_LAYOUT_INVALID: arch={architecture}; INPUT_UNION={unionSize}; expected={expectedUnionSize}.");
        Assert(mouseSize == expectedMouseSize,
            $"NATIVE_INPUT_LAYOUT_INVALID: arch={architecture}; MOUSEINPUT={mouseSize}; expected={expectedMouseSize}.");
        Assert(keyboardSize == expectedKeyboardSize,
            $"NATIVE_INPUT_LAYOUT_INVALID: arch={architecture}; KEYBDINPUT={keyboardSize}; expected={expectedKeyboardSize}.");
        Assert(hardwareSize == expectedHardwareSize,
            $"NATIVE_INPUT_LAYOUT_INVALID: arch={architecture}; HARDWAREINPUT={hardwareSize}; expected={expectedHardwareSize}.");

        return new NativeInputLayout(architecture, inputSize, unionSize, mouseSize, keyboardSize, hardwareSize);
    }

    private static void Assert(bool condition, string message)
    {
        if (!condition) throw new ProbeFailure(message);
    }

    private const ushort VK_CONTROL = 0x11;
    private const ushort VK_HOME = 0x24;
    private const ushort VK_END = 0x23;
    private const ushort VK_RETURN = 0x0D;
    private const ushort VK_SPACE = 0x20;
    private const uint INPUT_KEYBOARD = 1;
    private const uint KEYEVENTF_KEYUP = 0x0002;
    private const uint KEYEVENTF_UNICODE = 0x0004;

    [DllImport("user32.dll", SetLastError = true)]
    private static extern uint SendInput(uint count, Input[] inputs, int cbSize);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool SetForegroundWindow(IntPtr hwnd);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetWindowRect(IntPtr hwnd, out RectNative rect);

    [StructLayout(LayoutKind.Sequential)]
    private struct Input
    {
        public uint type;
        public InputUnion union;

        public static Input Unicode(char character, bool up) => new()
        {
            type = INPUT_KEYBOARD,
            union = new InputUnion
            {
                keyboard = new KeyboardInput
                {
                    scanCode = character,
                    flags = KEYEVENTF_UNICODE | (up ? KEYEVENTF_KEYUP : 0)
                }
            }
        };

        public static Input VirtualKey(ushort key, bool up) => new()
        {
            type = INPUT_KEYBOARD,
            union = new InputUnion
            {
                keyboard = new KeyboardInput
                {
                    virtualKey = key,
                    flags = up ? KEYEVENTF_KEYUP : 0
                }
            }
        };
    }

    [StructLayout(LayoutKind.Explicit)]
    private struct InputUnion
    {
        [FieldOffset(0)] public MouseInput mouse;
        [FieldOffset(0)] public KeyboardInput keyboard;
        [FieldOffset(0)] public HardwareInput hardware;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct MouseInput
    {
        public int dx;
        public int dy;
        public uint mouseData;
        public uint flags;
        public uint time;
        public UIntPtr extraInfo;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct KeyboardInput
    {
        public ushort virtualKey;
        public ushort scanCode;
        public uint flags;
        public uint time;
        public UIntPtr extraInfo;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct HardwareInput
    {
        public uint message;
        public ushort parameterLow;
        public ushort parameterHigh;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct RectNative
    {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }

    private readonly record struct NativeInputLayout(
        string Architecture,
        int InputSize,
        int UnionSize,
        int MouseSize,
        int KeyboardSize,
        int HardwareSize);

    private sealed class ProbeFailure : Exception
    {
        internal ProbeFailure(
            string message,
            string? stage = null,
            string code = "ASSERTION_FAILED",
            int? win32 = null,
            string classification = "probe-assertion") : base(message)
        {
            Stage = stage;
            Code = code;
            Win32 = win32;
            Classification = classification;
        }

        internal string? Stage { get; }
        internal string Code { get; }
        internal int? Win32 { get; }
        internal string Classification { get; }
    }

    private sealed record ProbeOptions(
        string OutputDirectory,
        double? ExpectedScale,
        BrowserThemeMode Theme,
        bool ScreenCapture,
        bool NoNavigation,
        bool ValidateInputLayoutOnly,
        bool ValidateDiagnosticsContractOnly)
    {
        public static ProbeOptions Parse(string[] args)
        {
            var output = Path.GetFullPath(Path.Combine(Environment.CurrentDirectory, "test-results", "native-browser-physical-ui"));
            double? expected = null;
            var theme = BrowserThemeMode.Dark;
            var screen = false;
            var noNavigation = false;
            var validateInputLayoutOnly = false;
            var validateDiagnosticsContractOnly = false;

            for (var i = 0; i < args.Length; i++)
            {
                switch (args[i])
                {
                    case "--output" when i + 1 < args.Length:
                        output = Path.GetFullPath(args[++i]);
                        break;
                    case "--expected-scale" when i + 1 < args.Length:
                        expected = double.Parse(args[++i], System.Globalization.CultureInfo.InvariantCulture);
                        break;
                    case "--theme" when i + 1 < args.Length:
                        theme = args[++i].ToLowerInvariant() switch
                        {
                            "light" => BrowserThemeMode.Light,
                            "system" => BrowserThemeMode.System,
                            _ => BrowserThemeMode.Dark
                        };
                        break;
                    case "--screen":
                        screen = true;
                        break;
                    case "--no-navigation":
                        noNavigation = true;
                        break;
                    case "--validate-input-layout-only":
                        validateInputLayoutOnly = true;
                        break;
                    case "--validate-diagnostics-contract-only":
                        validateDiagnosticsContractOnly = true;
                        break;
                }
            }

            return new ProbeOptions(
                output,
                expected,
                theme,
                screen,
                noNavigation,
                validateInputLayoutOnly,
                validateDiagnosticsContractOnly);
        }
    }
}
