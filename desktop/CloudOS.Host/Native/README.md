# NativeWindowManager

`NativeWindowManager` is the isolated Win32 boundary for CloudOS-managed native
application windows. It uses an initial `EnumWindows` snapshot plus out-of-process
`SetWinEventHook` callbacks on a dedicated message-loop thread.

## Trust boundary

The renderer must never call `TrackLaunchedProcess` directly and must never choose
an arbitrary PID or executable path. The native host must:

1. Resolve an opaque application ID through its authenticated backend catalog.
2. Admit only a direct executable descriptor with the launch contract below.
3. Use `CreateProcessW(CREATE_SUSPENDED)` with `STARTF_USESHOWWINDOW/SW_HIDE`.
4. Assign the suspended process to a `JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE` Job.
5. Track the exact root process before `ResumeThread`, then continuously enroll every
   descendant PID reported by `QueryInformationJobObject`.
6. Wait until the manager has observed and hidden a concrete HWND before reporting
   `managed: true` or giving the renderer an opaque session ID.

Each operation revalidates that the HWND is cached, still belongs to the registered
PID, and that the PID still has the same process start time and Windows session.
The host process cannot be registered, and targets above the host's token integrity
level are denied. Process and window counts are bounded.

Close first hides the launch group and uses bounded `WM_CLOSE`; a short grace period
must prove that the Job is empty. Tray behavior, a prompt, an ignored close, and every
other containment failure use Job/process-tree termination.
There is no input injection, privilege elevation, or cross-process `SetParent`. Hub
containment remains an owned top-level overlay: CloudOS removes the frame and taskbar
style, assigns its host owner, and bounds the window to the WebView surface. Detach,
attach failure, layout failure, correlation timeout, navigation reset, and host disposal
hide the HWND and terminate its exact tracked process tree. The host never restores an
application to an ordinary external window.

Events arrive on the manager's hook thread. A WinUI/WPF consumer must marshal UI
work to its dispatcher.

## Bridge lifecycle

The CloudOS bridge exposes containment only for opaque sessions created by that
trust flow:

- `native.session.attach { sessionId, bounds, visible? }`
- `native.session.layout { sessionId, bounds, visible }`
- `native.session.detach { sessionId }` (terminates; never exposes an external window)

`bounds` are CSS viewport coordinates. The WPF host converts them to device pixels,
intersects them with the WebView rectangle and recomputes them whenever its owner
window moves, resizes or crosses monitors. Public snapshots report
`hidden-quarantine`, `anchored-overlay`, or `terminated`. A pending hidden session
expires if the renderer does not attach it within the bounded deadline.

## Backend launch contract

The browser renderer sends only an opaque application ID and its user authorization.
The Host adds `X-CloudOS-Host-Token` to the backend POST. The authenticated backend
returns a descriptor and does **not** start a process or return a PID:

```json
{
  "launchKind": "windows-executable",
  "launchSpec": {
    "executable": "C:\\Program Files\\Example\\example.exe",
    "arguments": ["--profile", "CloudOS"],
    "workingDirectory": "C:\\Program Files\\Example"
  }
}
```

`arguments` is always a JSON argv array. Raw command-line strings are rejected; the
Host never splits on spaces or invokes a shell. `windows-shortcut-direct` is syntactically
accepted only when the backend has resolved a `.lnk` to an executable, proved there are
no shortcut arguments requiring lossy reparsing, and returns the target as the same
descriptor. A normal shell `.lnk` launch is not equivalent and must use
`launchKind: windows-shortcut`, `launchable: false`.

The catalog must publish these kinds as unavailable (`launchable: false`) and the
launch endpoint must reject them before starting anything:

- `windows-start-app`, UWP/AUMID and URI/protocol activation;
- ordinary `.lnk`/shell activation;
- any descriptor that may hand off to an already running singleton;
- any executable or descendant that is a shared broker.

`explorer.exe`, `RuntimeBroker.exe`, `ApplicationFrameHost.exe`, WSLg/RDP brokers and
similar processes multiplex windows from unrelated applications. Killing or adopting
one would cross the capability boundary; PID correlation cannot make those apps safe.
Supporting them requires an isolated desktop/session or a broker-specific surface API
that creates the new HWND hidden, proves launch ownership, and grants a one-window
capability before it can ever be shown. Until then they are discoverable but not
launchable in CloudOS.

## Structural limitation of the overlay architecture

The current Windows integration is an owned, borderless top-level overlay. It removes
the app from task switching, binds it to the CloudOS owner and continuously validates
owner, frame, Alt+Tab styles, visibility and bounds. It is still a real application
HWND, not pixels rendered inside the WebView process.

`CREATE_SUSPENDED`, hidden startup and a Job close the direct-process failure paths,
but they cannot prevent a generic single-instance executable from sending IPC to a
pre-existing process outside the Job. That external process could create or restore a
window which the Host cannot safely adopt or kill. Therefore a generic Windows scanner
cannot honestly infer strict containment from `.exe` or `.lnk` alone. If the product
contract requires a structural guarantee of zero external HWNDs, all generic Windows
entries remain `launchable: false` until a separate desktop/session with captured
rendering is implemented. The two direct launch kinds describe the Host boundary; they
are not, by themselves, proof that an arbitrary application is safe to publish.

## CloudOS Start integration

The frontend may publish discovered Windows entries in the normal CloudOS registry,
but only entries whose backend contract has `launchable: true` may open. No executable,
shortcut target, PID, or arbitrary HWND is copied into the Start-menu definition.
Opening an admitted entry routes it to `NativeAppWindow`, which attaches the quarantined
top-level window and keeps layout/visibility in sync with its CloudOS surface.

## Validation

Contract tests in `CloudOS.Host.Tests` execute a suspended process and a wrapper that
spawns a child with a real top-level HWND. They prove Job descendant correlation,
pre-attach hiding, argv JSON preservation and detection/quarantine when an attached
window restores an external frame. The same invariant rejects `WS_EX_APPWINDOW`.
They also verify broker/UWP/shell rejection,
`managed` gating and terminal failure policy. A full product smoke test must additionally
inspect the real taskbar/Alt+Tab UI. `detach` must terminate the fixture.

## Broker and WSLg limitation

WSLg application windows are normally surfaced by Windows-side WSLg/RDP processes,
not by the Linux guest PID passed to `wsl.exe`. PID-only attribution cannot safely
distinguish multiple apps sharing a broker. The current contract intentionally rejects
that path; Linux GUI must use the separate contained Xpra transport.
