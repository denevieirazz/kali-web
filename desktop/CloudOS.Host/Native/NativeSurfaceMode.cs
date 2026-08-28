namespace CloudOS.Host.Native;

/// <summary>
/// Selects how a real Windows application is presented inside the CloudOS shell.
/// NativeOverlay is the production default: Windows/DWM keeps rendering the real HWND and
/// CloudOS only owns its lifecycle, bounds, visibility and focus. CapturedSurface remains an
/// explicit compatibility/debug fallback while the old capture pipeline is retired.
/// </summary>
internal enum NativeSurfaceRenderMode
{
    NativeOverlay,
    CapturedSurface
}

internal static class NativeSurfaceMode
{
    internal const string EnvironmentVariable = "CLOUDOS_NATIVE_SURFACE_MODE";

    internal static NativeSurfaceRenderMode Current => Resolve(
        Environment.GetEnvironmentVariable(EnvironmentVariable));

    internal static NativeSurfaceRenderMode Resolve(string? value)
    {
        if (string.Equals(value?.Trim(), "capture", StringComparison.OrdinalIgnoreCase)
            || string.Equals(value?.Trim(), "captured-surface", StringComparison.OrdinalIgnoreCase))
        {
            return NativeSurfaceRenderMode.CapturedSurface;
        }

        // Fail toward the native Windows path. Unknown/empty values must never silently enable
        // frame capture because capture is now a fallback rather than the application runtime.
        return NativeSurfaceRenderMode.NativeOverlay;
    }

    internal static string Describe(NativeSurfaceRenderMode mode) =>
        mode == NativeSurfaceRenderMode.CapturedSurface
            ? "captured-surface"
            : "anchored-overlay";
}
