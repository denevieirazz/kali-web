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

    internal bool Passed { get; set; }
    internal string Mode { get; set; } = "physical";
    internal bool PhysicalValidation { get; set; } = true;
    internal string Stage { get; set; } = "startup";
    internal bool PhysicalScreenCapture { get; set; }
    internal double? ReportedScalePercent { get; set; }
    internal double? ExpectedScalePercent { get; set; }
    internal string ShortInput { get; set; } = string.Empty;
    internal int LongInputLength { get; set; }
    internal NativeInputReport? NativeInput { get; set; }
    internal PhysicalInputContext? PhysicalInputContext { get; set; }
    internal Dictionary<string, OmniboxVisualReport> OmniboxVisuals { get; } = new(StringComparer.Ordinal);
    internal Dictionary<string, SurfaceVisualReport> SurfaceVisuals { get; } = new(StringComparer.Ordinal);

    internal ProbeErrorReport? Error
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

    internal List<string> Checks { get; } = [];
    internal List<string> Artifacts { get; } = [];

    internal void RegisterSurface(string key, SurfaceVisualReport report, bool finalMeasurement)
    {
        SurfaceVisuals[key] = report;
        if (finalMeasurement && !string.IsNullOrWhiteSpace(report.FailureClassification))
            PendingSurfaceClassification = report.FailureClassification;
    }

    internal async Task WriteAsync(string outputDirectory)
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
internal sealed record SurfaceSamplePointReport(
    int X,
    int Y,
    RgbReport Color,
    bool MatchesExpected,
    bool White,
    bool InsideWebView);

internal sealed record SurfaceVisualReport
{
    internal string Stage { get; init; } = string.Empty;
    internal RectReport? WindowBounds { get; init; }
    internal RectReport? HubBounds { get; init; }
    internal RectReport? WebViewBoundsDip { get; init; }
    internal RectReport? WebViewBoundsPixels { get; init; }
    internal double DpiScale { get; init; }
    internal bool NavigationCompleted { get; init; }
    internal bool DocumentConfirmed { get; init; }
    internal RectReport? SamplingRegion { get; init; }
    internal IReadOnlyList<SurfaceSamplePointReport> SamplePoints { get; init; } = [];
    internal RgbReport? ExpectedColor { get; init; }
    internal IReadOnlyList<RgbReport> ObservedColors { get; init; } = [];
    internal RgbReport? SampledWebViewPixel => ObservedColors.FirstOrDefault();
    internal double MatchRatio { get; init; }
    internal double WhitePixelRatio { get; init; }
    internal double OverlapPixels { get; init; }
    internal double SeparationPixels { get; init; }
    internal bool WebViewVisible { get; init; }
    internal string? FailureClassification { get; init; }
    internal string? FailureDetail { get; init; }
}
