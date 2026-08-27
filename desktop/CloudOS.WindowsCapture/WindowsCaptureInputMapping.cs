namespace CloudOS.WindowsCapture;

public sealed record WindowsCaptureInputGeometry(
    int SourcePixelWidth,
    int SourcePixelHeight,
    int CropPixelX,
    int CropPixelY,
    int CropPixelWidth,
    int CropPixelHeight,
    double SurfaceCssWidth,
    double SurfaceCssHeight)
{
    public WindowsCaptureInputGeometry Validate()
    {
        if (SourcePixelWidth is < 1 or > 32768) throw new ArgumentOutOfRangeException(nameof(SourcePixelWidth));
        if (SourcePixelHeight is < 1 or > 32768) throw new ArgumentOutOfRangeException(nameof(SourcePixelHeight));
        if (CropPixelX < 0 || CropPixelY < 0) throw new ArgumentOutOfRangeException("Crop origin must be non-negative.");
        if (CropPixelWidth < 1 || CropPixelHeight < 1) throw new ArgumentOutOfRangeException("Crop dimensions must be positive.");
        if ((long)CropPixelX + CropPixelWidth > SourcePixelWidth || (long)CropPixelY + CropPixelHeight > SourcePixelHeight)
            throw new ArgumentOutOfRangeException("Crop rectangle must remain within the captured source texture.");
        if (SurfaceCssWidth <= 0 || double.IsNaN(SurfaceCssWidth) || double.IsInfinity(SurfaceCssWidth))
            throw new ArgumentOutOfRangeException(nameof(SurfaceCssWidth));
        if (SurfaceCssHeight <= 0 || double.IsNaN(SurfaceCssHeight) || double.IsInfinity(SurfaceCssHeight))
            throw new ArgumentOutOfRangeException(nameof(SurfaceCssHeight));
        return this;
    }

    public static WindowsCaptureInputGeometry FullFrame(
        int sourcePixelWidth,
        int sourcePixelHeight,
        double surfaceCssWidth,
        double surfaceCssHeight) =>
        new WindowsCaptureInputGeometry(
            sourcePixelWidth,
            sourcePixelHeight,
            0,
            0,
            sourcePixelWidth,
            sourcePixelHeight,
            surfaceCssWidth,
            surfaceCssHeight).Validate();
}

public sealed record WindowsCapturePointerMapping(
    double LocalCssX,
    double LocalCssY,
    int SourcePixelX,
    int SourcePixelY,
    double NormalizedX,
    double NormalizedY);

/// <summary>
/// Maps pointer coordinates from the CloudOS surface element into the captured texture.
/// This class intentionally stops at source-texture pixels. Translating those pixels into
/// Win32 client/screen coordinates requires a separately validated HWND/DPI/non-client
/// transform and must not be approximated with global SendInput.
/// </summary>
public static class WindowsCaptureInputMapper
{
    public static bool TryMapPointer(
        WindowsCaptureInputGeometry geometry,
        double localCssX,
        double localCssY,
        out WindowsCapturePointerMapping? mapping)
    {
        ArgumentNullException.ThrowIfNull(geometry);
        geometry.Validate();
        mapping = null;

        if (!double.IsFinite(localCssX) || !double.IsFinite(localCssY)) return false;
        if (localCssX < 0 || localCssY < 0 || localCssX >= geometry.SurfaceCssWidth || localCssY >= geometry.SurfaceCssHeight)
            return false;

        var normalizedX = localCssX / geometry.SurfaceCssWidth;
        var normalizedY = localCssY / geometry.SurfaceCssHeight;
        var relativeX = Math.Min(
            geometry.CropPixelWidth - 1,
            (int)Math.Floor(normalizedX * geometry.CropPixelWidth));
        var relativeY = Math.Min(
            geometry.CropPixelHeight - 1,
            (int)Math.Floor(normalizedY * geometry.CropPixelHeight));

        mapping = new WindowsCapturePointerMapping(
            localCssX,
            localCssY,
            geometry.CropPixelX + relativeX,
            geometry.CropPixelY + relativeY,
            normalizedX,
            normalizedY);
        return true;
    }
}
