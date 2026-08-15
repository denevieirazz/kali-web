namespace CloudOS.Host.Browser;

public readonly record struct BrowserSurfaceRect(double X, double Y, double Width, double Height)
{
    public double Left => X;
    public double Top => Y;
    public double Right => X + Width;
    public double Bottom => Y + Height;
}

public readonly record struct BrowserSurfacePoint(int X, int Y);
public readonly record struct BrowserSurfaceRgb(int R, int G, int B);

public readonly record struct BrowserSurfaceColorEvaluation(
    double MatchRatio,
    double WhitePixelRatio,
    bool MeetsExpectedColorRatio,
    bool WhiteBackgroundDetected);

public static class BrowserSurfaceGeometry
{
    public const double DefaultInsetRatio = 0.20d;
    public const int DefaultGridColumns = 5;
    public const int DefaultGridRows = 5;
    public const int DefaultColorTolerance = 18;
    public const double DefaultMinimumMatchRatio = 0.80d;
    public const double DefaultMaximumWhiteRatio = 0.10d;

    public static BrowserSurfaceRect ScaleDipRect(
        BrowserSurfaceRect dipRect,
        double dpiScaleX,
        double dpiScaleY)
    {
        if (!IsFinitePositive(dpiScaleX) || !IsFinitePositive(dpiScaleY))
            throw new ArgumentOutOfRangeException(nameof(dpiScaleX), "DPI scale must be finite and positive.");

        return new BrowserSurfaceRect(
            dipRect.X * dpiScaleX,
            dipRect.Y * dpiScaleY,
            dipRect.Width * dpiScaleX,
            dipRect.Height * dpiScaleY);
    }

    public static BrowserSurfaceRect SelectInteriorRegion(
        BrowserSurfaceRect pixelBounds,
        double insetRatio = DefaultInsetRatio)
    {
        if (!IsUsable(pixelBounds))
            throw new ArgumentOutOfRangeException(nameof(pixelBounds), "Sampling bounds must have finite positive size.");
        if (!double.IsFinite(insetRatio) || insetRatio < 0d || insetRatio >= 0.45d)
            throw new ArgumentOutOfRangeException(nameof(insetRatio));

        var insetX = Math.Max(8d, pixelBounds.Width * insetRatio);
        var insetY = Math.Max(8d, pixelBounds.Height * insetRatio);
        insetX = Math.Min(insetX, Math.Max(0d, pixelBounds.Width / 2d - 2d));
        insetY = Math.Min(insetY, Math.Max(0d, pixelBounds.Height / 2d - 2d));

        var result = new BrowserSurfaceRect(
            pixelBounds.X + insetX,
            pixelBounds.Y + insetY,
            pixelBounds.Width - insetX * 2d,
            pixelBounds.Height - insetY * 2d);

        if (!IsUsable(result))
            throw new ArgumentOutOfRangeException(nameof(pixelBounds), "Sampling region collapsed after safe inset.");
        return result;
    }

    public static IReadOnlyList<BrowserSurfacePoint> BuildSampleGrid(
        BrowserSurfaceRect region,
        int columns = DefaultGridColumns,
        int rows = DefaultGridRows)
    {
        if (!IsUsable(region))
            throw new ArgumentOutOfRangeException(nameof(region));
        if (columns < 2 || columns > 9) throw new ArgumentOutOfRangeException(nameof(columns));
        if (rows < 2 || rows > 9) throw new ArgumentOutOfRangeException(nameof(rows));

        var points = new List<BrowserSurfacePoint>(columns * rows);
        for (var row = 0; row < rows; row++)
        {
            for (var column = 0; column < columns; column++)
            {
                var x = region.Left + ((column + 0.5d) / columns) * region.Width;
                var y = region.Top + ((row + 0.5d) / rows) * region.Height;
                points.Add(new BrowserSurfacePoint((int)Math.Round(x), (int)Math.Round(y)));
            }
        }
        return points;
    }

    public static BrowserSurfaceColorEvaluation EvaluateColors(
        IReadOnlyList<BrowserSurfaceRgb> observed,
        BrowserSurfaceRgb expected,
        int tolerance = DefaultColorTolerance,
        double minimumMatchRatio = DefaultMinimumMatchRatio,
        double maximumWhiteRatio = DefaultMaximumWhiteRatio)
    {
        ArgumentNullException.ThrowIfNull(observed);
        if (observed.Count == 0) throw new ArgumentException("At least one sample is required.", nameof(observed));
        if (tolerance < 0 || tolerance > 64) throw new ArgumentOutOfRangeException(nameof(tolerance));
        if (minimumMatchRatio is < 0d or > 1d) throw new ArgumentOutOfRangeException(nameof(minimumMatchRatio));
        if (maximumWhiteRatio is < 0d or > 1d) throw new ArgumentOutOfRangeException(nameof(maximumWhiteRatio));

        var matches = 0;
        var white = 0;
        foreach (var color in observed)
        {
            if (Math.Abs(color.R - expected.R) <= tolerance &&
                Math.Abs(color.G - expected.G) <= tolerance &&
                Math.Abs(color.B - expected.B) <= tolerance)
                matches++;
            if (color.R >= 245 && color.G >= 245 && color.B >= 245)
                white++;
        }

        var matchRatio = matches / (double)observed.Count;
        var whiteRatio = white / (double)observed.Count;
        return new BrowserSurfaceColorEvaluation(
            matchRatio,
            whiteRatio,
            matchRatio >= minimumMatchRatio,
            whiteRatio > maximumWhiteRatio);
    }

    public static double HorizontalOverlapPixels(BrowserSurfaceRect left, BrowserSurfaceRect right)
    {
        if (!IsUsable(left) || !IsUsable(right)) return 0d;
        var verticalOverlap = Math.Min(left.Bottom, right.Bottom) - Math.Max(left.Top, right.Top);
        if (verticalOverlap <= 0d) return 0d;
        return Math.Max(0d, Math.Min(left.Right, right.Right) - Math.Max(left.Left, right.Left));
    }

    public static double SeparationPixels(BrowserSurfaceRect left, BrowserSurfaceRect right) =>
        Math.Max(0d, right.Left - left.Right);

    public static bool Contains(BrowserSurfaceRect container, BrowserSurfaceRect content, double tolerance = 0d) =>
        content.Left >= container.Left - tolerance &&
        content.Top >= container.Top - tolerance &&
        content.Right <= container.Right + tolerance &&
        content.Bottom <= container.Bottom + tolerance;

    private static bool IsUsable(BrowserSurfaceRect value) =>
        double.IsFinite(value.X) &&
        double.IsFinite(value.Y) &&
        double.IsFinite(value.Width) &&
        double.IsFinite(value.Height) &&
        value.Width > 0d && value.Height > 0d;

    private static bool IsFinitePositive(double value) => double.IsFinite(value) && value > 0d;
}
