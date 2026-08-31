# CloudOS Flutter Presentation V19

This directory is the **presentation layer only** for CloudOS.

The validated native C++ shell remains authoritative for lifecycle, recovery,
window management, Windows/WSL integration, file operations, deployment and
shell activation. Flutter is intentionally treated as a replaceable UI client.

## What is implemented

The standalone preview currently renders:

- CloudOS desktop wallpaper/surface;
- bottom taskbar and workspace indicators;
- Start/Search with Windows, Linux and CloudOS app badges;
- draggable Files visual shell with Windows + Ubuntu/WSL navigation;
- Quick Settings;
- Notification Center;
- desktop app shortcuts;
- keyboard preview shortcuts (`Ctrl+Alt+E`, `Ctrl+Alt+Q`, `Esc`);
- animated/translucent panels using stock Flutter only.

No third-party runtime package is required by the UI itself.

## Native bridge contract

The Dart side reserves the method channel:

`cloudos/native/v19`

Methods currently consumed by the presentation layer:

- `getApps`
- `getSystemSnapshot`
- `launchApp`

If no native Flutter host is attached, the bridge deliberately falls back to
preview data and performs no launch side effects. This makes the UI safe to run
before wiring it into the native CloudOS core.

The future Windows host should implement these methods by adapting existing
CloudOS C++ authorities instead of duplicating app discovery, WSL logic or
system state in Dart.

## Preview on Windows

Requirements:

- Flutter 3.44.7 (pinned for V19 validation)
- Visual Studio with Desktop development with C++
- Windows SDK

From the repository root:

```powershell
pwsh -File .\scripts\flutter\preview-cloudos-flutter-v19.ps1 -Run
```

The script generates the standard Flutter Windows runner locally if it does not
exist. The generated `windows/` host is intentionally ignored by Git in V19;
this milestone validates the visual layer before committing native host
integration.

For validation without opening the UI:

```powershell
pwsh -File .\scripts\flutter\preview-cloudos-flutter-v19.ps1
```

That runs `flutter pub get`, `flutter analyze`, `flutter test`, and a release
Windows build.

## Architecture boundary

```text
Flutter presentation
  Desktop / Start / Taskbar / Files chrome / Panels
                 |
          MethodChannel v19
                 |
Native adapter (next stage)
                 |
Existing CloudOS native C++ core
  V9 health / V10 lifecycle / V11 supervisor
  V13 deployment / V14 activation
  V16 integration / V17 unified app discovery
```

V19 must not directly implement Winlogon, registry mutation, WSL package
management, WinGet operations, shell recovery or deployment logic in Dart.
