# NativeWindowManager

`NativeWindowManager` is the isolated Win32 boundary for CloudOS-managed native
application windows. It uses an initial `EnumWindows` snapshot plus out-of-process
`SetWinEventHook` callbacks on a dedicated message-loop thread.

## Trust boundary

The renderer must never call `TrackLaunchedProcess` directly and must never choose
an arbitrary PID or executable path. The native host should:

1. Resolve an opaque application ID through an allowlisted catalog.
2. Launch the resolved executable with a fixed argument schema.
3. Pass the returned `System.Diagnostics.Process` to `TrackLaunchedProcess`.
4. Give the renderer only the resulting window snapshots/handles for that app.

Each operation revalidates that the HWND is cached, still belongs to the registered
PID, and that the PID still has the same process start time and Windows session.
The host process cannot be registered, and targets above the host's token integrity
level are denied. Process and window counts are bounded.
Close is a bounded `WM_CLOSE`; there is no forced termination, input injection,
privilege elevation, or cross-process `SetParent`. Hub containment is a reversible
owned top-level overlay: CloudOS removes the frame, positions the window over a
renderer-provided slot bounded to the WebView, and restores its original owner,
styles, bounds and placement on detach or host disposal. Apps that reject those
changes remain ordinary external windows.

Events arrive on the manager's hook thread. A WinUI/WPF consumer must marshal UI
work to its dispatcher.

## Minimal host usage

```csharp
using System.Diagnostics;
using CloudOS.Host.Native;

using (var windows = new NativeWindowManager())
{
    windows.WindowChanged += (sender, change) =>
    {
        // DispatcherQueue.TryEnqueue(() => PublishToTrustedRenderer(change));
    };

    // `launchSpec` must come from the host-owned allowlisted app catalog.
    Process app = Process.Start(launchSpec);
    windows.TrackLaunchedProcess(app);

    windows.Refresh();
    foreach (NativeWindowSnapshot window in windows.GetWindows(app.Id))
    {
        string error;
        windows.TryFocus(window.Handle, out error);
    }
}
```

Do not expose `Process.Start`, `TrackLaunchedProcess`, or a generic HWND adoption
operation through WebView2. Expose narrow commands such as `focusWindow(appId,
windowId)` after resolving both IDs in the native host.

The CloudOS bridge exposes containment only for opaque sessions already created by
that trust flow:

- `native.session.attach { sessionId, bounds, visible? }`
- `native.session.layout { sessionId, bounds, visible }`
- `native.session.detach { sessionId }`

`bounds` are CSS viewport coordinates. The WPF host converts them to device pixels,
intersects them with the WebView rectangle and recomputes them whenever its owner
window moves, resizes or crosses monitors. Public snapshots report `contained`,
`containmentMode` (`anchored-overlay` or `external`) and `visible`.

## Validation

The source intentionally uses APIs available to both modern .NET for Windows and
the Windows .NET Framework compiler, so it can be syntax/P/Invoke validated without
the final WinUI host project:

```powershell
& "$env:WINDIR\Microsoft.NET\Framework64\v4.0.30319\csc.exe" `
  /nologo /target:library `
  /out:"$env:TEMP\CloudOS.Host.Native.dll" `
  .\desktop\CloudOS.Host\Native\NativeWindowManager.cs
```

For a functional smoke test, launch a known non-elevated fixture such as Notepad
from a small host console, register the exact returned `Process`, wait for an
`Added` event, then invoke attach, layout, detach, restore, maximize, minimize,
focus, and close in that order. Also verify these negative cases:

- a random HWND is rejected;
- the CloudOS host PID cannot be registered;
- an elevated/different-session target is not controllable by the normal host;
- a stale HWND or reused PID is rejected;
- a hung window makes close time out without killing the process;
- exceeding configured process/window limits does not add more capabilities.

## WSLg limitation

WSLg application windows are normally surfaced by Windows-side WSLg/RDP processes,
not by the Linux guest PID passed to `wsl.exe`. PID-only attribution therefore is
not sufficient to safely distinguish multiple WSLg apps sharing a broker process.
Do not register a shared WSLg broker wholesale. A later WSLg adapter must correlate
the launch operation with newly-created HWNDs and add a separate, explicit window
capability before those windows can use this manager's operations.
