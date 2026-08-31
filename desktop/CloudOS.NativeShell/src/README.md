# CloudOS.NativeShell source map

This directory contains both the **current compiled native shell** and historical source files kept for reference. Do not infer authority from filename age or from a file merely existing here.

## Source of truth

The definitive compile graph is:

```text
desktop/CloudOS.NativeShell/CloudOS.NativeShell.vcxproj
```

The current process entry point is:

```text
main_shell_v2.cpp
```

`src/main.cpp` is historical and is **not** a `<ClCompile>` item in the current project. Likewise, older implementation generations can remain in this directory without participating in the release. Before editing a versioned implementation, confirm the exact file in the `.vcxproj`.

## High-level ownership

- `main_shell_v2.cpp` — process bootstrap, primary shell composition and top-level lifecycle wiring.
- `native_desktop_*` — desktop window/surface, context menu and drop target.
- `native_taskbar_*` — taskbar/AppBar and hover previews.
- `native_start_*` — Start menu, indexing and MRU/recommendation support.
- `native_files_*` / `native_file_*` — first-party Files UI, navigation, preview, search and file operations.
- `native_window_manager*` — HWND inventory, workspace ownership, recovery and workspace integration.
- `native_workspace_*` — overview, profiles, automation, labels and workspace studio.
- `native_session_continuity_*` — checkpoints, restore ledger and continuity UI.
- `native_control_plane_service.*`, `native_command_center_window.*`, `native_quick_settings_*` — system control plane.
- `native_watchdog.*`, `native_health_bootstrap_v9.h`, `native_lifecycle_v10.h` — in-process health/lifecycle support. External recovery authority is `CloudOS.Supervisor.exe` in `../CloudOS.NativeRecovery`.
- `native_browser_window.*` — the only intentional WebView2 consumer in the native shell product.

For a task-oriented map, read `docs/native/CODEMAP.md` before opening implementation files.

## Editing rules

1. Preserve Win32/C++ as the desktop authority.
2. Do not re-add the legacy web desktop or WebView host to the compile graph.
3. Do not rename/move implementation files only for cosmetic organization; the project file and contracts intentionally make the active graph explicit.
4. Keep V9 health ABI, V10 lifecycle semantics and V11 supervisor protocol backward compatible unless the milestone explicitly versions them.
5. Run `scripts/native/test-native-contract-suite.ps1` before building.
