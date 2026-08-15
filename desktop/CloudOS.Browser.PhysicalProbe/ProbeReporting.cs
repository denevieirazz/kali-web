using System.Text.Json;

namespace CloudOS.Browser.PhysicalProbe;

internal sealed class ProbeRunReport
{
    public bool Passed { get; set; }
    public string Mode { get; init; } = "physical";
    public bool PhysicalValidation { get; init; } = true;
    public string Stage { get; set; } = "startup";
    public bool PhysicalScreenCapture { get; init; }
    public double? ReportedScalePercent { get; set; }
    public double? ExpectedScalePercent { get; init; }
    public string ShortInput { get; init; } = string.Empty;
    public int LongInputLength { get; init; }
    public NativeInputReport? NativeInput { get; set; }
    public PhysicalInputContext? PhysicalInputContext { get; set; }
    public ProbeErrorReport? Error { get; set; }
    public List<string> Checks { get; } = [];
    public List<string> Artifacts { get; } = [];

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
}

internal sealed record NativeInputReport(
    string Architecture,
    int InputSize,
    int UnionSize,
    int MouseInputSize,
    int KeyboardInputSize,
    int HardwareInputSize);

internal sealed record ProbeErrorReport(
    string Code,
    string Message,
    int? Win32,
    string Classification);
