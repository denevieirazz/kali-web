# CloudOS Visual Platform V7

Status: implementation track on `work/files-storage-v5` after the V5 linker/lifecycle fixes.

## Goal

Move the native CloudOS shell from a dark Win32 utility look to a coherent commercial desktop language while keeping the production shell native C++/Win32/DWM. The React desktop remains reference-only.

## Visual foundation

### Materials and depth

CloudOS owns a layered graphite material system (`BgSolid` -> `BgPrimary` -> `BgSecondary` -> `BgTertiary` -> `BgElevated`) with indigo/cyan ambient light. Cards use a short shadow, a one-pixel specular top edge and rounded geometry. Long-lived windows use `DWMSBT_MAINWINDOW`; transient flyouts use `DWMSBT_TRANSIENTWINDOW`.

Important API detail: the documented `DWM_SYSTEMBACKDROP_TYPE` enum does **not** contain `DWMSBT_ACRYLIC`. On Windows 11, `DWMSBT_TRANSIENTWINDOW` maps to the desktop Acrylic material and `DWMSBT_MAINWINDOW` maps to Mica. CloudOS uses the semantic enum values rather than magic integer aliases.

### Reveal highlight

Owner-drawn buttons now support a cursor-centered radial highlight clipped to the native control. This is implemented in `native_theme.h` using GDI+ `PathGradientBrush`, so Start, Quick Settings, Settings and other surfaces that share `WebSkin::PaintOwnerDrawButton` inherit the effect without a browser compositor.

Next integration point: apply the same reveal primitive to Start cards, taskbar groups and Files cards using their existing hit-test rectangles.

### Motion

`WebSkin` exposes compositor-friendly easing primitives and an 8 ms target animation cadence. The 8 ms value is a target for active animations, **not a promise of fixed 120 FPS**. Final presentation cadence remains controlled by DWM and the monitor refresh rate. DirectComposition is the preferred path for scale/opacity transforms on complex flyouts rather than permanently running high-frequency Win32 timers.

### Floating taskbar/dock

Target composition:
- keep AppBar registration so maximized windows respect reserved work area;
- paint the visible taskbar as a rounded dock inset from the AppBar host;
- use transparent/inert host space outside the dock and return `HTTRANSPARENT` outside interactive geometry;
- 10 DIP bottom gap, ~20 DIP corners;
- workspace pills with animated active indicator;
- open-app indicator is a short indigo luminous stroke rather than a filled rectangular task state;
- preserve grouped tasks, overflow, DWM previews and multi-monitor behavior.

This must not regress the V4 AppBar/window-management contracts.

## Desktop widgets

The desktop widget layer remains first-party native and should be lightweight:
- clock/date card;
- CPU/RAM activity rings using `NativeSystemStats`;
- media card driven by GSMTC;
- optional calendar/task adapter later;
- dynamic day/night wallpaper policy in `NativeWallpaperManager`;
- video wallpaper is opt-in and must suspend when obscured, on battery saver, remote session or low-power mode.

## Native Platform Services

### Global media control (GSMTC)

`native_media_control_v7.h` uses `Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager` through C++/WinRT. It caches title, artist, album, source app, playback state and control capabilities. Refresh/control operations run on background MTA threads so the Win32 UI thread is never blocked by `.get()` on WinRT async operations.

The service fails closed when Windows denies the `globalMediaControl` capability or no session exists. CloudOS must display “no active media” rather than crashing.

### Wi-Fi

The V4 control backend already uses the native WLAN API:
- `WlanOpenHandle`;
- `WlanEnumInterfaces`;
- `WlanGetAvailableNetworkList`;
- `WlanConnect` for saved profiles;
- `WlanDisconnect`.

CloudOS intentionally keeps unsaved-network credential entry in the official Windows flow for now. Newer Windows releases apply privacy/location policy to Wi-Fi enumeration, and synthesizing profile XML with user passwords inside the shell would need a separate credential/security design. Do not silently store Wi-Fi passwords in CloudOS state.

### Bluetooth

Planned implementation uses `Windows.Devices.Enumeration` plus `DeviceInformationPairing` for modern Classic/BLE discovery and pairing. The legacy `BluetoothAPIs.h` path can remain a compatibility/provider layer but is not the only pairing model.

### Per-app audio mixer

`native_audio_mixer_v7.h` uses:
- `IAudioSessionManager2`;
- `IAudioSessionEnumerator`;
- `IAudioSessionControl2`;
- `ISimpleAudioVolume`.

It enumerates render sessions, resolves process identity where possible, reports active/mute/volume state and can change volume/mute per process. Quick Settings will consume this service as the application mixer panel.

### Windows Search SystemIndex

`native_windows_search_v7.h` queries the official Windows Search catalog instead of recursively walking disks. It uses `ISearchManager`, `ISearchCatalogManager`, `ISearchQueryHelper` and the OLE DB connection string returned by the query helper to read `System.ItemName`, `System.ItemPathDisplay` and `System.ItemUrl` from `SystemIndex`.

The Start integration must execute this provider on a worker thread, merge/index-rank results with CloudOS apps and preserve bounded result counts.

### Shell context menus

For Windows Shell-backed content, the existing `IExplorerBrowser` provider already owns Explorer/Shell selection behavior. Where CloudOS owns a fallback file surface, the native context-menu bridge should use `IShellFolder::GetUIObjectOf` and `IContextMenu/IContextMenu2/IContextMenu3` so registered verbs/extensions are preserved.

CloudOS Drive remains security-separated: arbitrary shell extension handlers must not bypass its reparse-point and trash protections.

### Session lifecycle

CloudOS already persists its own session/continuity ledger and handles power/session shutdown paths. V7 adds `WTSRegisterSessionNotification` as the correct source for lock/unlock/logon/logoff/session-switch notifications.

Restart Manager is **not** a replacement for the CloudOS session ledger. It is useful for coordinated application restart/resource ownership (`RmStartSession`, `RmRegisterResources`, `RmShutdown`, `RmRestart`) and should only be used where that model fits. CloudOS window restoration remains under Session Continuity.

## Rollout order

1. Visual foundation: Reveal Highlight + correct DWM material semantics.
2. Native platform service layer: GSMTC + per-app CoreAudio + SystemIndex.
3. Quick Settings V7: media card + per-app mixer + existing native Wi-Fi.
4. Floating Taskbar/Dock V7 without regressing AppBar, previews, grouping or multi-monitor.
5. Desktop Widgets V7: clock, activity rings, media card.
6. Search V7 merge into Start and Shell context-menu bridge in Files where CloudOS owns content.
7. WTS session notifications and optional Restart Manager integration for compatible child applications.
8. DirectComposition motion pass for scale/opacity transforms and refresh-aware animations.

## Non-negotiable quality gates

- `/W4 /WX` Release x64 remains clean.
- No `SetParent` cross-process hosting.
- Browser remains in-process WebView2.
- No fake Acrylic enum or undocumented magic integer when a documented DWM enum exists.
- No blocking GSMTC calls on the UI thread.
- Search is bounded and off the UI thread.
- Wi-Fi credentials are never persisted as plaintext CloudOS state.
- CloudOS Drive security boundaries remain intact.
- Manual close must never be interpreted as a crash by the watchdog.
