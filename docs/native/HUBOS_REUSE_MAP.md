# HubOS -> CloudOS Native reuse map

This document records which ideas from `denevieirazz/hubOS` are useful to the native CloudOS rewrite and, just as importantly, which implementation layers must not be carried forward.

## Architectural rule

CloudOS product runtime is C++/Win32. React, Vite, Node, WebView2, xterm.js, WinUI/XAML and managed C# services are not runtime dependencies of the native shell.

HubOS is therefore treated as a source of proven Windows/WSL algorithms and behavioral requirements, not as a framework dependency.

## Already ported

### ConPTY terminal core

HubOS sources:
- `Core/Terminal/Win32ConPtyNative.cs`
- `Core/Terminal/ConPtySession.cs`

CloudOS target:
- `desktop/CloudOS.NativeRuntime/src/cloudos_native_terminal.cpp`

Status:
- Ported to C++.
- Uses `CreatePseudoConsole`, `STARTUPINFOEX`, pipe I/O and resize.
- Child process is created suspended, assigned to a kill-on-close Job Object, then resumed.
- No xterm.js, WebSocket, Node or managed P/Invoke layer.

### Event-driven HWND discovery

HubOS sources:
- `Services/WindowCaptureService.cs`
- `Services/Win32WindowManager.cs`

CloudOS target:
- `desktop/CloudOS.NativeRuntime/src/cloudos_native_window_events.cpp`

Status:
- Ported to C++.
- Uses `SetWinEventHook` rather than polling.
- Tracks create/destroy/show/hide/foreground/location events.
- Uses `DWMWA_EXTENDED_FRAME_BOUNDS` with `GetWindowRect` fallback.
- Universal `SetParent` is explicitly not the CloudOS application model.

### WSL platform API

HubOS sources:
- `Services/WslService.cs`
- `Services/WslManager.cs`
- `Services/WslProcessRunner.cs`

CloudOS target:
- `desktop/CloudOS.NativeRuntime/src/cloudos_native_wsl.cpp`

Status:
- Port in progress.
- Uses the Windows `wslapi.h` contract directly where available.
- The WSL API module is resolved dynamically so machines without WSL fail as a capability check, not as a loader failure.
- `wsl.exe` remains acceptable only for functionality not exposed by `wslapi`, and for ConPTY-backed interactive WSL terminal profiles.

## Next ports

### Native window/workspace manager

HubOS sources:
- `Services/TilingService.cs`
- `Services/TilingWindowManager.cs`
- `Services/GlobalHookService.cs`
- `Services/GlobalHotkeyService.cs`
- `Services/Win32KeyboardHook.cs`

Port the behavior, not the managed classes:
- master-stack tiling
- monitor work-area aware placement
- floating-window classification
- focus-next / swap-master
- snap regions
- global CloudOS hotkeys

CloudOS implementation must use real top-level HWNDs. Reparenting is opt-in compatibility only.

### WSLg application discovery

HubOS source:
- `Services/WindowCaptureService.cs`

Useful behavior:
- recognize `RAIL_WINDOW`
- event-driven lifecycle instead of title polling
- preserve WSLg z-order constraints

CloudOS improvement:
- correlate new HWNDs using event time, class, process metadata, title and launch capability rather than title substring alone.

### Hybrid process manager

HubOS source:
- `Services/HybridProcessManager.cs`

Port:
- Windows process snapshot
- CPU delta sampling
- WSL process inventory
- process lifecycle aggregation

Do not port string-shell execution as the primary transport.

### Filesystem and path translation

HubOS sources:
- `Services/HybridFileSystem.cs`
- `Services/PathTranslator.cs`

Port:
- Windows drive enumeration
- `\\wsl$` / `\\wsl.localhost` recognition
- Windows <-> `/mnt/<drive>` syntactic translation
- bounded copy operations

Redesign:
- path canonicalization and traversal policy
- Docker transport
- error model

### Linux application metadata

HubOS source:
- `Services/DesktopEntryParser.cs`

Port:
- `[Desktop Entry]` parser
- Name / Exec / Icon / Categories / NoDisplay
- bounded icon loading

Do not port:
- interpolated shell command construction
- xterm/WebView rendering
- Skia dependency unless a native-image requirement justifies it

## Do not bring into the native core

- WinUI/XAML shell composition
- WebView2 wallpaper/runtime surfaces
- xterm.js terminal renderer
- React/Vite/Node service boundaries
- universal `SetParent` embedding
- polling loops for HWND discovery
- unstructured shell command interpolation

## Native replacements

| HubOS layer | CloudOS Native replacement |
| --- | --- |
| WinUI/XAML shell | Win32 + DirectComposition/Direct2D/DirectWrite |
| C# P/Invoke ConPTY | C++ ConPTY runtime |
| xterm.js | native VT parser + native text renderer |
| ProcessStartInfo WSL wrapper | `wslapi` where supported; tightly-scoped `wsl.exe` fallback |
| title-poll HWND hunt | `SetWinEventHook` registry and correlation |
| universal `SetParent` | real top-level HWND management; compatibility attach only |
| managed global hooks | C++ Win32 input/hotkey layer |
| XamlRoot DPI | per-monitor-v2 + `WM_DPICHANGED` / monitor APIs |

## Target application model

A normal Windows program should remain a normal top-level Windows window. CloudOS owns the desktop experience around it: discovery, placement, z-order, focus, workspace membership, tiling, lifecycle, taskbar representation and policy.

This is the key change that removes the old embedded-screen compatibility ceiling.
