using System.Text.Json;
using System.Text.Json.Serialization;

namespace CloudOS.Browser.PhysicalProbe;

internal sealed class ProbeRunReport
{
    private ProbeErrorReport? _error;

    internal ProbeRunReport()
    {
        Current = this;
    }

    [JsonIgnore]
    internal static ProbeRunReport? Current { get; private set; }

    [JsonIgnore]
    internal string? PendingSurfaceClassification { get; set; }

    public bool Passed { get; set; }
    public string Mode { get; set; } = "physical";
    public bool PhysicalValidation { get; set; } = true;
    public string Stage { get; set; } = "startup";
    public bool PhysicalScreenCapture { get; set; }
    public double? ReportedScalePercent { get; set; }
    public double? ExpectedScalePercent { get; set; }
    public string ShortInput { get; set; } = string.Empty;
    public int LongInputLength { get; set; }
    public NativeInputReport? NativeInput { get; set; }
    public PhysicalInputContext? PhysicalInputContext { get; set; }
    public Dictionary<string, OmniboxVisualReport> OmniboxVisuals { get; } = new(StringComparer.Ordinal);
    public Dictionary<string, SurfaceVisualReport> SurfaceVisuals { get; } = new(StringComparer.Ordinal);

    public ProbeErrorReport? Error
    {
        get => _error;
        set
        {
            if (value is null)
            {
                _error = null;
                PendingSurfaceClassification = null;
                return;
            }

            var classification = PendingSurfaceClassification ?? InferSurfaceClassification(value.Message) ?? value.Classification;
            _error = value with { Classification = classification };
        }
    }

    public List<string> Checks { get; } = [];
    public List<string> Artifacts { get; } = [];

    internal void RegisterSurface(string key, SurfaceVisualReport report, bool finalMeasurement)
    {
        SurfaceVisuals[key] = report;
        if (finalMeasurement && !string.IsNullOrWhiteSpace(report.FailureClassification))
            PendingSurfaceClassification = report.FailureClassification;
    }

    public async Task WriteAsync(string outputDirectory)
    {
        Directory.CreateDirectory(outputDirectory);
        var path = Path.Combine(outputDirectory, "validation.json");
        var json = JsonSerializer.Serialize(this, new JsonSerializerOptions
        {
            WriteIndented = true,
            PropertyNamingPolicy = JsonNamingPolicy.CamelCase
        });
        await File.WriteAllTextAsync(path, json);
    }

    private static string? InferSurfaceClassification(string message)
    {
        string[] known =
        [
            "webview-not-rendered",
            "sentinel-navigation-not-completed",
            "sample-outside-webview",
            "dpi-coordinate-mismatch",
            "hub-webview-overlap",
            "white-host-background-visible",
            "unexpected-rendered-color",
            "capture-unavailable"
        ];
        return known.FirstOrDefault(code => message.Contains(code, StringComparison.Ordinal));
    }
}

internal sealed record ProbeErrorReport(
    string Code,
    string Message,
    int? Win32,
    string Classification);

internal sealed record NativeInputReport(
    string Architecture,
    int InputSize,
    int UnionSize,
    int MouseSize,
    int KeyboardSize,
    int HardwareSize);

internal sealed record RectReport(double X, double Y, double Width, double Height);
internal sealed record RgbReport(int R, int G, int B);

internal sealed record OmniboxVisualReport(
    string Stage,
    double TextBoxHeight,
    double ContentViewportHeight,
    RectReport ContentViewport,
    RectReport RenderedText,
    RectReport? Caret,
    RectReport? Selection,
    double FormattedTextHeight,
    double ClipToleranceDip);

internal sealed record SurfaceSamplePointReport(
    int X,
    int Y,
    RgbReport Color,
    bool MatchesExpected,
    bool White,
    bool InsideWebView);

internal sealed record SurfaceVisualReport
{
    public string Stage { get; init; } = string.Empty;
    public RectReport? WindowBounds { get; init; }
    public RectReport? HubBounds { get; init; }
    public RectReport? WebViewBoundsDip { get; init; }
    public RectReport? WebViewBoundsPixels { get; init; }
    public double DpiScale { get; init; }
    public bool NavigationCompleted { get; init; }
    public bool DocumentConfirmed { get; init; }
    public RectReport? SamplingRegion { get; init; }
    public IReadOnlyList<SurfaceSamplePointReport> SamplePoints { get; init; } = [];
    public RgbReport? ExpectedColor { get; init; }
    public IReadOnlyList<RgbReport> ObservedColors { get; init; } = [];
    public RgbReport? SampledWebViewPixel => ObservedColors.FirstOrDefault();
    public double MatchRatio { get; init; }
    public double WhitePixelRatio { get; init; }
    public double OverlapPixels { get; init; }
    public double SeparationPixels { get; init; }
    public bool WebViewVisible { get; init; }
    public string? FailureClassification { get; init; }
    public string? FailureDetail { get; init; }
}
