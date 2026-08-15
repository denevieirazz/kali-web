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
using Microsoft.Web.WebView2.Wpf;

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
            Assert(root.TryGetProperty("omniboxVisuals", out _), "diagnostics contract perdeu a seção de métricas da omnibox.");
            Assert(root.TryGetProperty("surfaceVisuals", out _), "diagnostics contract perdeu a seção de métricas de superfícies.");
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
        if (options.ExpectedScale is null || Math.Abs(options.ExpectedScale.Value - 100d) > 0.01d)
            throw new ProbeFailure(
                "PHYSICAL_SCALE_CONTRACT_FAILED: esta candidata deve ser validada somente em escala 100%.",
                "scale-contract",
                "PHYSICAL_SCALE_CONTRACT_FAILED",
                null,
                "physical-scale-not-100");

        SetStage("native-input-layout");
        var inputLayout = ValidateNativeInputLayout();
        if (_report is not null) _report.NativeInput = ToReport(inputLayout);

        var tempRoot = Path.Combine(Path.GetTempPath(), "CloudOS", "BrowserPhysicalProbe", Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(tempRoot);
        BrowserWindow? window = null;
        CoreWebView2BrowserExtension? unmanagedProbeExtension = null;
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
            await PumpAsync(500);

            var scale = VisualTreeHelper.GetDpi(window).DpiScaleX * 100d;
            if (_report is not null) _report.ReportedScalePercent = Math.Round(scale, 2);
            if (Math.Abs(scale - 100d) > 2.5d)
                throw new ProbeFailure(
                    $"DPI_SCALE_MISMATCH: esperado 100% e o Windows reportou {scale:0.##}%.",
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
            Assert(address.ActualHeight >= 38, $"AddressBox muito baixo: {address.ActualHeight:0.##}.");
            Assert(shell.ActualHeight >= 43, $"AddressShell muito baixo: {shell.ActualHeight:0.##}.");
            Assert(shell.ActualWidth >= 320, $"Omnibox estreita em janela normal: {shell.ActualWidth:0.##}.");
            Assert(address.Template.FindName("PART_ContentHost", address) is FrameworkElement,
                "PART_ContentHost da omnibox ausente.");

            SetStage("omnibox-empty");
            address.Clear();
            System.Windows.Input.Keyboard.ClearFocus();
            window.Focus();
            await PumpAsync(100);
            Assert(placeholder.Visibility == Visibility.Visible, "Placeholder vazio não está visível.");
            RecordOmnibox("empty", MeasureOmnibox(address, "empty", requireCaret: false, requireSelection: false));
            CaptureElement(window, shell, options, "01-omnibox-empty-closeup.png", 12);

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
            await PumpAsync(120);
            Assert(address.Text == ShortInput, $"Digitação curta divergente: '{address.Text}'.");
            RecordOmnibox("typed", MeasureOmnibox(address, "typed", requireCaret: true, requireSelection: false));
            CaptureElement(window, shell, options, "02-omnibox-typed-closeup.png", 12);

            SetStage("sendinput-ctrl-a");
            Chord(VK_CONTROL, 'A');
            await PumpAsync(80);
            Assert(address.SelectionLength == address.Text.Length, "Ctrl+A não selecionou tudo.");
            RecordOmnibox("selected", MeasureOmnibox(address, "selected", requireCaret: true, requireSelection: true));
            CaptureElement(window, shell, options, "03-omnibox-selected-closeup.png", 12);

            SetStage("sendinput-clipboard");
            Chord(VK_CONTROL, 'C');
            await PumpAsync(60);
            Assert(Clipboard.ContainsText() && Clipboard.GetText() == ShortInput, "Ctrl+C falhou.");
            Clipboard.SetText(PasteInput);
            Chord(VK_CONTROL, 'A');
            Chord(VK_CONTROL, 'V');
            await PumpAsync(100);
            Assert(address.Text == PasteInput, "Ctrl+V falhou.");
            RecordOmnibox("paste", MeasureOmnibox(address, "paste", requireCaret: true, requireSelection: false));
            Capture(window, options, "04-paste.png");

            SetStage("sendinput-long-url");
            Chord(VK_CONTROL, 'A');
            SendText(LongInput);
            await PumpAsync(120);
            Assert(address.Text == LongInput, "URL longa foi truncada ou alterada.");
            PressKey(VK_HOME);
            await PumpAsync(70);
            Assert(address.CaretIndex == 0, $"Home falhou: {address.CaretIndex}.");
            RecordOmnibox("long-url-home", MeasureOmnibox(address, "long-url-home", requireCaret: true, requireSelection: false));
            Capture(window, options, "05-long-url-home.png");

            PressKey(VK_END);
            await PumpAsync(70);
            Assert(address.CaretIndex == address.Text.Length, $"End falhou: {address.CaretIndex}/{address.Text.Length}.");
            RecordOmnibox("long-url-end", MeasureOmnibox(address, "long-url-end", requireCaret: true, requireSelection: false));
            Capture(window, options, "06-long-url-end.png");

            if (!options.NoNavigation)
            {
                SetStage("sendinput-enter-navigation");
                Chord(VK_CONTROL, 'A');
                SendText(ShortInput);
                PressKey(VK_RETURN);
                await PumpAsync(2300);
                Assert(address.Text.Contains("youtube.com", StringComparison.OrdinalIgnoreCase),
                    $"Enter não navegou para youtube.com: '{address.Text}'.");
                Capture(window, options, "07-after-navigation.png");
            }

            SetStage("compact-layout");
            window.Width = 820;
            window.Height = 620;
            await PumpAsync(220);
            Assert(shell.ActualWidth >= 250, $"Omnibox estreita demais no modo compacto: {shell.ActualWidth:0.##}.");
            RecordOmnibox("compact", MeasureOmnibox(address, "compact", requireCaret: false, requireSelection: false));
            Capture(window, options, "08-compact.png");

            SetStage("theme-layout-evidence");
            window.Width = 1280;
            window.Height = 800;
            SetTheme(window, BrowserThemeMode.Dark);
            await PumpAsync(150);
            Capture(window, options, "09-dark-normal.png");
            window.Width = 820;
            window.Height = 620;
            await PumpAsync(150);
            Capture(window, options, "10-dark-compact.png");
            window.Width = 1280;
            window.Height = 800;
            SetTheme(window, BrowserThemeMode.Light);
            await PumpAsync(150);
            Capture(window, options, "11-light-normal.png");
            window.Width = 820;
            window.Height = 620;
            await PumpAsync(150);
            Capture(window, options, "12-light-compact.png");

            SetStage("browser-surfaces");
            window.Width = 1280;
            window.Height = 800;
            SetTheme(window, options.Theme);
            await PumpAsync(220);

            var menuButton = Require<Button>(window, "BrowserMenuButton");
            var menuPopup = Require<Popup>(window, "BrowserMenuPopup");
            var menuNewTab = Require<Button>(window, "MenuNewTabButton");
            var menuDownloads = Require<Button>(window, "MenuDownloadsButton");
            var menuExtensions = Require<Button>(window, "MenuExtensionsButton");
            var menuSettings = Require<Button>(window, "MenuSettingsButton");
            var menuClearData = Require<Button>(window, "MenuClearDataButton");
            var downloadsButton = Require<Button>(window, "DownloadsButton");
            var extensionsButton = Require<Button>(window, "ExtensionsButton");
            var hubPanel = Require<Border>(window, "HubPanel");
            var hubTitle = Require<TextBlock>(window, "HubTitle");
            var hubSubtitle = Require<TextBlock>(window, "HubSubtitle");
            var hubContent = Require<StackPanel>(window, "HubContent");
            var webViewHost = Require<Grid>(window, "WebViewHost");
            var activeWebView = SurfaceVisualDiagnostics.FindDescendants<WebView2>(webViewHost)
                .FirstOrDefault(view => view.Visibility == Visibility.Visible)
                ?? throw new ProbeFailure("WebView2 ativo ausente antes da validação de superfícies.");

            SetStage("menu-bounds-keyboard");
            Focus(window, menuButton);
            PressKey(VK_SPACE);
            await PumpAsync(180);
            Assert(menuPopup.IsOpen, "Menu principal não abriu por entrada física.");
            var menuRoot = menuPopup.Child as FrameworkElement
                ?? throw new ProbeFailure("Conteúdo visual do menu principal ausente.");
            Assert(menuRoot.ActualWidth >= 340, $"Menu principal estreito: {menuRoot.ActualWidth:0.##}.");
            Assert(menuRoot.ActualHeight >= 220, $"Menu principal sem altura útil: {menuRoot.ActualHeight:0.##}.");
            Assert(menuDownloads.IsVisible && menuExtensions.IsVisible && menuSettings.IsVisible,
                "Menu perdeu itens obrigatórios.");
            RecordSurface("menu", MeasureSurface("menu", () => SurfaceVisualDiagnostics.EnsureMenuInsideWindow(window, menuRoot)));
            var menuScroll = SurfaceVisualDiagnostics.FindDescendant<ScrollViewer>(menuRoot)
                ?? throw new ProbeFailure("ScrollViewer interno do menu ausente.");
            Assert(menuScroll.VerticalScrollBarVisibility == ScrollBarVisibility.Auto,
                "Menu não habilita rolagem vertical interna automática.");

            PressKey(VK_END);
            await PumpAsync(110);
            Assert(menuClearData.IsKeyboardFocusWithin, "End não alcançou o último item do menu por teclado.");
            MeasureSurfaceAction("menu:end", () => SurfaceVisualDiagnostics.EnsureElementVisibleInScrollViewer(menuScroll, menuClearData, "menu:end"));
            PressKey(VK_HOME);
            await PumpAsync(110);
            Assert(menuNewTab.IsKeyboardFocusWithin, "Home não retornou ao primeiro item do menu por teclado.");
            MeasureSurfaceAction("menu:home", () => SurfaceVisualDiagnostics.EnsureElementVisibleInScrollViewer(menuScroll, menuNewTab, "menu:home"));
            Capture(window, options, "13-menu-window.png");
            CaptureElement(window, menuRoot, options, "13-menu-complete.png", 0);
            menuPopup.IsOpen = false;
            await PumpAsync(80);

            SetStage("webview-surface-sentinel");
            try
            {
                await SurfaceVisualDiagnostics.PrepareWebViewSentinelAsync(activeWebView);
            }
            catch (Exception error) when (error is InvalidOperationException or COMException)
            {
                throw new ProbeFailure(
                    $"WEBVIEW_SENTINEL_FAILED: {SanitizeDiagnostic(error.Message)}",
                    "webview-surface-sentinel",
                    "WEBVIEW_SENTINEL_FAILED",
                    null,
                    "webview-physical-surface-unavailable");
            }
            await PumpAsync(180);

            SetStage("downloads-surface");
            Focus(window, downloadsButton);
            PressKey(VK_SPACE);
            await PumpAsync(240);
            Assert(hubPanel.Visibility == Visibility.Visible, "Hub de Downloads não ficou visível.");
            Assert(string.Equals(hubTitle.Text, "Downloads", StringComparison.Ordinal),
                $"Hub de Downloads divergente: '{hubTitle.Text}'.");
            Assert(
                FindDescendantByName<FrameworkElement>(hubContent, "DownloadsEmptyState") is not null ||
                hubContent.Children.Count > 0,
                "Área de Downloads não possui estado visível.");
            RecordSurface("downloads", MeasureSurface("downloads", () => SurfaceVisualDiagnostics.EnsureHubAndWebView(window, hubPanel, activeWebView, "downloads")));
            Capture(window, options, "14-downloads.png");

            SetStage("extensions-unmanaged-fixture");
            var profile = activeWebView.CoreWebView2?.Profile
                ?? throw new ProbeFailure("Perfil WebView2 ativo ausente para prova de ownership.");
            try
            {
                unmanagedProbeExtension = await SurfaceVisualDiagnostics.AddUnmanagedProbeExtensionAsync(profile, tempRoot);
            }
            catch (Exception error) when (error is ArgumentException or InvalidOperationException or IOException or COMException)
            {
                throw new ProbeFailure(
                    $"UNMANAGED_EXTENSION_FIXTURE_FAILED: {error.GetType().Name}",
                    "extensions-unmanaged-fixture",
                    "UNMANAGED_EXTENSION_FIXTURE_FAILED",
                    null,
                    "webview-extension-fixture-failed");
            }

            SetStage("extensions-surface");
            Focus(window, extensionsButton);
            PressKey(VK_SPACE);
            await PumpAsync(650);
            Assert(hubPanel.Visibility == Visibility.Visible, "Hub de Extensões não ficou visível.");
            Assert(string.Equals(hubTitle.Text, "Extensões", StringComparison.Ordinal),
                $"Hub de Extensões divergente: '{hubTitle.Text}'.");
            var extensionLoad = FindDescendantByName<Button>(hubContent, "ExtensionLoadButton");
            Assert(extensionLoad is { IsVisible: true, IsEnabled: true },
                "Área de Extensões não expõe carregamento local.");
            Assert(!hubSubtitle.Text.Contains("não está disponível", StringComparison.OrdinalIgnoreCase),
                $"API de Extensões indisponível na prova física: '{hubSubtitle.Text}'.");

            var ownershipManager = new BrowserExtensionManager(environment.UserDataFolder);
            Assert(!ownershipManager.IsManagedExtension(unmanagedProbeExtension.Id),
                "Fixture WebView2 externa foi classificada incorretamente como gerenciada pelo CloudOS.");
            var extensionButtons = SurfaceVisualDiagnostics.FindDescendants<Button>(hubContent)
                .Where(button => button.Tag is string id && id.Equals(unmanagedProbeExtension.Id, StringComparison.Ordinal))
                .ToList();
            Assert(extensionButtons.Count > 0, "Componente WebView2 não gerenciado não apareceu na lista de Extensões.");
            Assert(!extensionButtons.Any(button => string.Equals(button.Content as string, "Remover", StringComparison.Ordinal)),
                "Extensão interna/não gerenciada expõe ação Remover.");
            var unmanagedMarker = SurfaceVisualDiagnostics.FindDescendants<TextBlock>(hubContent)
                .FirstOrDefault(text => text.Text.Contains("não gerenciado pelo CloudOS", StringComparison.OrdinalIgnoreCase));
            Assert(unmanagedMarker is { IsVisible: true },
                "Extensão não gerenciada não possui diferenciação visual de ownership.");
            foreach (var remove in SurfaceVisualDiagnostics.FindDescendants<Button>(hubContent)
                         .Where(button => string.Equals(button.Content as string, "Remover", StringComparison.Ordinal)))
            {
                Assert(remove.Tag is string id && ownershipManager.IsManagedExtension(id),
                    "Existe botão Remover associado a extensão fora de package-* controlado pelo Browser.");
            }
            RecordSurface("extensions", MeasureSurface("extensions", () => SurfaceVisualDiagnostics.EnsureHubAndWebView(window, hubPanel, activeWebView, "extensions")));
            Capture(window, options, "15-extensions.png");

            try
            {
                await unmanagedProbeExtension.RemoveAsync();
                unmanagedProbeExtension = null;
            }
            catch (Exception error) when (error is InvalidOperationException or COMException)
            {
                throw new ProbeFailure(
                    $"UNMANAGED_EXTENSION_FIXTURE_CLEANUP_FAILED: {error.GetType().Name}",
                    "extensions-unmanaged-fixture-cleanup",
                    "UNMANAGED_EXTENSION_FIXTURE_CLEANUP_FAILED");
            }

            SetStage("settings-surface");
            Focus(window, menuButton);
            PressKey(VK_SPACE);
            await PumpAsync(170);
            Assert(menuPopup.IsOpen, "Menu principal não reabriu para Configurações.");
            PressKey(VK_END);
            await PumpAsync(90);
            PressKey(VK_UP);
            await PumpAsync(90);
            Assert(menuSettings.IsKeyboardFocusWithin, "Configurações não foi alcançada pelo teclado no menu rolável.");
            PressKey(VK_SPACE);
            await PumpAsync(260);
            Assert(hubPanel.Visibility == Visibility.Visible, "Hub de Configurações não ficou visível.");
            Assert(string.Equals(hubTitle.Text, "Configurações", StringComparison.Ordinal),
                $"Hub de Configurações divergente: '{hubTitle.Text}'.");
            RecordSurface("settings", MeasureSurface("settings", () => SurfaceVisualDiagnostics.EnsureHubAndWebView(window, hubPanel, activeWebView, "settings")));
            Capture(window, options, "16-settings.png");

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
                    "rendered-text-content-viewport",
                    "top-bottom-clip-tolerance",
                    "caret-visible",
                    "selection-visible",
                    "omnibox-closeups",
                    "sendinput-unicode",
                    "typing",
                    "ctrl+a",
                    "ctrl+c",
                    "ctrl+v",
                    "home",
                    "end",
                    "enter-navigation",
                    "scale-100-only",
                    "normal-width",
                    "compact-width",
                    "dark",
                    "light",
                    "menu-complete",
                    "menu-within-browser-window",
                    "menu-internal-scroll",
                    "menu-keyboard-first-last",
                    "downloads-surface",
                    "downloads-webview-visible-nonwhite",
                    "extensions-surface",
                    "extensions-webview-visible-nonwhite",
                    "extensions-unmanaged-no-remove",
                    "extensions-remove-package-only",
                    "settings",
                    "settings-webview-visible-nonwhite"
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
            if (unmanagedProbeExtension is not null)
            {
                try { await unmanagedProbeExtension.RemoveAsync(); } catch { }
            }

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

    private static OmniboxVisualReport MeasureOmnibox(
        TextBox address,
        string stage,
        bool requireCaret,
        bool requireSelection)
    {
        try
        {
            return OmniboxVisualDiagnostics.Measure(address, stage, requireCaret, requireSelection);
        }
        catch (InvalidOperationException error)
        {
            throw new ProbeFailure(
                $"OMNIBOX_RENDER_BOUNDS_FAILED: stage={stage}; detail={SanitizeDiagnostic(error.Message)}",
                $"omnibox:{stage}",
                "OMNIBOX_RENDER_BOUNDS_FAILED",
                null,
                "rendered-text-or-caret-clipping");
        }
    }

    private static SurfaceVisualReport MeasureSurface(string stage, Func<SurfaceVisualReport> measure)
    {
        try
        {
            return measure();
        }
        catch (InvalidOperationException error)
        {
            throw new ProbeFailure(
                $"SURFACE_VISUAL_FAILED: stage={stage}; detail={SanitizeDiagnostic(error.Message)}",
                $"surface:{stage}",
                "SURFACE_VISUAL_FAILED",
                null,
                "surface-bounds-visibility-or-white-regression");
        }
    }

    private static void MeasureSurfaceAction(string stage, Action measure)
    {
        try
        {
            measure();
        }
        catch (InvalidOperationException error)
        {
            throw new ProbeFailure(
                $"SURFACE_VISUAL_FAILED: stage={stage}; detail={SanitizeDiagnostic(error.Message)}",
                $"surface:{stage}",
                "SURFACE_VISUAL_FAILED",
                null,
                "surface-keyboard-scroll-regression");
        }
    }

    private static void RecordOmnibox(string key, OmniboxVisualReport report)
    {
        if (_report is not null) _report.OmniboxVisuals[key] = report;
    }

    private static void RecordSurface(string key, SurfaceVisualReport report)
    {
        if (_report is not null) _report.SurfaceVisuals[key] = report;
    }

    private static string SanitizeDiagnostic(string value)
    {
        var clean = new string(value.Where(ch => !char.IsControl(ch)).ToArray()).Trim();
        return clean.Length <= 180 ? clean : clean[..180] + "…";
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

    private static T? FindDescendantByName<T>(DependencyObject root, string name) where T : FrameworkElement
    {
        if (root is T element && string.Equals(element.Name, name, StringComparison.Ordinal))
            return element;

        var children = VisualTreeHelper.GetChildrenCount(root);
        for (var index = 0; index < children; index++)
        {
            var found = FindDescendantByName<T>(VisualTreeHelper.GetChild(root, index), name);
            if (found is not null) return found;
        }

        return null;
    }

    private static void SetTheme(BrowserWindow window, BrowserThemeMode mode)
    {
        var method = typeof(BrowserWindow).GetMethod(
            "SetChromeTheme",
            BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic)
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
        if (options.ScreenCapture) CaptureScreen(window, path);
        else CaptureWpf(window, path);
        RegisterArtifact(name);
    }

    private static void CaptureElement(Window window, FrameworkElement element, ProbeOptions options, string name, int paddingPixels)
    {
        var path = Path.Combine(options.OutputDirectory, name);
        if (options.ScreenCapture) CaptureElementScreen(element, path, paddingPixels);
        else CaptureElementWpf(element, path);
        RegisterArtifact(name);
    }

    private static void RegisterArtifact(string name)
    {
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

    private static void CaptureElementWpf(FrameworkElement element, string path)
    {
        element.UpdateLayout();
        var source = PresentationSource.FromVisual(element);
        var transform = source?.CompositionTarget?.TransformToDevice ?? Matrix.Identity;
        var width = Math.Max(1, (int)Math.Round(element.ActualWidth * transform.M11));
        var height = Math.Max(1, (int)Math.Round(element.ActualHeight * transform.M22));
        var bitmap = new RenderTargetBitmap(width, height, 96d * transform.M11, 96d * transform.M22, PixelFormats.Pbgra32);
        bitmap.Render(element);
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

    private static void CaptureElementScreen(FrameworkElement element, string path, int paddingPixels)
    {
        element.UpdateLayout();
        var topLeft = element.PointToScreen(new Point(0, 0));
        var bottomRight = element.PointToScreen(new Point(element.ActualWidth, element.ActualHeight));
        var left = (int)Math.Floor(Math.Min(topLeft.X, bottomRight.X)) - paddingPixels;
        var top = (int)Math.Floor(Math.Min(topLeft.Y, bottomRight.Y)) - paddingPixels;
        var right = (int)Math.Ceiling(Math.Max(topLeft.X, bottomRight.X)) + paddingPixels;
        var bottom = (int)Math.Ceiling(Math.Max(topLeft.Y, bottomRight.Y)) + paddingPixels;
        var width = Math.Max(1, right - left);
        var height = Math.Max(1, bottom - top);

        using var bitmap = new Bitmap(width, height, System.Drawing.Imaging.PixelFormat.Format32bppArgb);
        using (var graphics = Graphics.FromImage(bitmap))
            graphics.CopyFromScreen(left, top, 0, 0, new System.Drawing.Size(width, height), CopyPixelOperation.SourceCopy);
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
    private const ushort VK_UP = 0x26;
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
            var output = Path.GetFullPath(Path.Combine(
                Environment.CurrentDirectory,
                "test-results",
                "native-browser-physical-ui"));
            double? expected = null;
            var theme = BrowserThemeMode.Dark;
            var screen = false;
            var noNavigation = false;
            var validateInputLayoutOnly = false;
            var validateDiagnosticsContractOnly = false;

            for (var index = 0; index < args.Length; index++)
            {
                switch (args[index])
                {
                    case "--output" when index + 1 < args.Length:
                        output = Path.GetFullPath(args[++index]);
                        break;
                    case "--expected-scale" when index + 1 < args.Length:
                        expected = double.Parse(args[++index], System.Globalization.CultureInfo.InvariantCulture);
                        break;
                    case "--theme" when index + 1 < args.Length:
                        theme = args[++index].ToLowerInvariant() switch
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
