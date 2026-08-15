using System.Runtime.CompilerServices;
using CloudOS.Host.Browser;

internal static class BrowserSurfaceGeometryContract
{
    [ModuleInitializer]
    internal static void Initialize()
    {
        var dip = new BrowserSurfaceRect(10, 20, 100, 50);
        var pixels = BrowserSurfaceGeometry.ScaleDipRect(dip, 1.5, 1.25);
        Assert(Near(pixels.X, 15) && Near(pixels.Y, 25), "DIP origin was not converted with the supplied DPI scale.");
        Assert(Near(pixels.Width, 150) && Near(pixels.Height, 62.5), "DIP size was not converted with the supplied DPI scale.");

        var bounds = new BrowserSurfaceRect(100, 200, 500, 300);
        var region = BrowserSurfaceGeometry.SelectInteriorRegion(bounds);
        Assert(BrowserSurfaceGeometry.Contains(bounds, region), "Safe sampling region escaped the WebView bounds.");
        Assert(region.Left > bounds.Left && region.Top > bounds.Top && region.Right < bounds.Right && region.Bottom < bounds.Bottom,
            "Safe sampling region must stay away from borders and overlays.");

        var grid = BrowserSurfaceGeometry.BuildSampleGrid(region);
        Assert(grid.Count == 25, "Physical sampling grid must contain 25 points.");
        Assert(grid.All(point => point.X > region.Left && point.X < region.Right && point.Y > region.Top && point.Y < region.Bottom),
            "Sampling grid contains a point outside the safe region.");

        var expected = new BrowserSurfaceRgb(25, 50, 74);
        var unexpected = new BrowserSurfaceRgb(53, 139, 202);
        var mostlyExpected = Enumerable.Repeat(expected, 20)
            .Concat(Enumerable.Repeat(unexpected, 5))
            .ToArray();
        var accepted = BrowserSurfaceGeometry.EvaluateColors(mostlyExpected, expected);
        Assert(Near(accepted.MatchRatio, 0.8), "Expected-color match ratio is incorrect.");
        Assert(accepted.MeetsExpectedColorRatio, "80% sentinel match must satisfy the minimum ratio.");
        Assert(!accepted.WhiteBackgroundDetected, "Non-white sentinel samples were misclassified as Host white background.");

        var tooManyUnexpected = Enumerable.Repeat(expected, 19)
            .Concat(Enumerable.Repeat(unexpected, 6))
            .ToArray();
        Assert(!BrowserSurfaceGeometry.EvaluateColors(tooManyUnexpected, expected).MeetsExpectedColorRatio,
            "Unexpected rendered colors were accepted below the 80% minimum.");

        var whiteSurface = Enumerable.Repeat(new BrowserSurfaceRgb(255, 255, 255), 4)
            .Concat(Enumerable.Repeat(expected, 21))
            .ToArray();
        Assert(BrowserSurfaceGeometry.EvaluateColors(whiteSurface, expected).WhiteBackgroundDetected,
            "White Host background ratio was not detected.");

        var web = new BrowserSurfaceRect(0, 0, 600, 400);
        var overlappingHub = new BrowserSurfaceRect(590, 0, 300, 400);
        var separatedHub = new BrowserSurfaceRect(612, 0, 300, 400);
        Assert(Near(BrowserSurfaceGeometry.HorizontalOverlapPixels(web, overlappingHub), 10),
            "Hub/WebView overlap calculation is incorrect.");
        Assert(Near(BrowserSurfaceGeometry.SeparationPixels(web, separatedHub), 12),
            "Hub/WebView separation calculation is incorrect.");
        Assert(Near(BrowserSurfaceGeometry.HorizontalOverlapPixels(web, separatedHub), 0),
            "Separated surfaces were reported as overlapping.");

        Console.WriteLine("PASS browser surface DPI sampling color and overlap geometry");
    }

    private static bool Near(double left, double right) => Math.Abs(left - right) < 0.001;

    private static void Assert(bool condition, string message)
    {
        if (!condition) throw new InvalidOperationException(message);
    }
}
