# CloudOS FlutterShell refactoring notes

## Goal

Keep behavior stable while reducing oversized Dart files. Prefer structural extraction before behavioral redesign.

## Current module boundaries

- `lib/shell/cloudos_shell.dart`: shell state, bridge loading, keyboard shortcuts, app/window orchestration, transient panel switching.
- `lib/widgets/desktop_surface.dart`: private desktop presentation helpers used by the shell (wallpaper, desktop icons, desktop status).
- `lib/widgets/files_window.dart`: `FilesWindow` public widget and its navigation/filter/view state.
- `lib/widgets/files_window_parts.dart`: private presentation helpers for the files window (title bar, sidebar, toolbar, grid/list, empty/status surfaces).

The extracted files use Dart `part`/`part of` deliberately so private symbols and existing call sites remain unchanged during the first decomposition pass.

## Refactoring rule

For each oversized widget:

1. Keep the public widget and mutable state in the original file.
2. Move private, presentation-only helpers into a colocated part file without renaming symbols.
3. Do not change strings, callbacks, keyboard shortcuts, bridge calls, layout values, or public constructors in the same commit as the extraction.
4. Only after the presentation tests stay green should parts be promoted to independent imported widgets where that improves reuse.

## Validation

From `desktop/CloudOS.FlutterShell` run:

```bash
flutter analyze
flutter test
```

The existing `test/shell_smoke_test.dart` is the primary regression suite for the desktop presentation and System Broker bridge contracts.

## Next candidates by size

At the start of this pass the remaining large presentation files included:

- `lib/widgets/start_panel.dart` (~19 KB)
- `lib/widgets/cloud_taskbar.dart` (~12 KB)
- `lib/widgets/quick_settings_panel.dart` (~11 KB)
- `lib/widgets/notification_center.dart` (~8 KB)

Apply the same state-vs-presentation split incrementally rather than rewriting several behaviors at once.
