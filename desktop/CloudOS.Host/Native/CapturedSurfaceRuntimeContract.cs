using CloudOS.WindowsCapture;

namespace CloudOS.Host.Native;

public sealed record CapturedSurfaceSessionSnapshot(
    string SurfaceId,
    int Generation,
    long SourceWindowHandle,
    long PresentationWindowHandle,
    WindowsCaptureSnapshot Capture,
    WindowsCaptureSurfaceCoordinatorSnapshot Presentation,
    bool InputActive);

/// <summary>
/// Narrow runtime boundary used by the bridge adapter. Keeping lifecycle coordination at
/// this boundary makes attach/layout/close ordering testable without constructing a physical
/// Windows Graphics Capture session.
/// </summary>
public interface ICapturedSurfaceSessionRuntime
{
    CapturedSurfaceSessionSnapshot CreateAndStart(
        string surfaceId,
        int generation,
        long sourceWindowHandle,
        long ownerWindowHandle,
        WindowsCapturePresentationLayout initialLayout,
        WindowsFrameHealthOptions? frameHealthOptions = null);

    bool TryGetSnapshot(
        string surfaceId,
        int generation,
        out CapturedSurfaceSessionSnapshot? snapshot);

    void ApplyLayout(
        string surfaceId,
        int generation,
        WindowsCapturePresentationLayout layout);

    bool RoutePointer(
        string surfaceId,
        int generation,
        long sequence,
        WindowsCapturePointerEventKind kind,
        WindowsCapturePointerButton button,
        int wheelDelta,
        bool shift,
        bool control,
        bool alt,
        double surfaceCssWidth,
        double surfaceCssHeight,
        double localCssX,
        double localCssY);

    bool RouteKey(
        string surfaceId,
        int generation,
        long sequence,
        WindowsCaptureKeyEventKind kind,
        int virtualKey,
        int scanCode,
        bool extended,
        bool repeat);

    bool Close(string surfaceId, int generation);
}
