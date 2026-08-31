# CloudOS Native Desktop — delivery roadmap

This roadmap describes the **current C++/Win32 native product**. Historical React/WPF/Node plans are compatibility material and do not override this document.

## Current validated baseline

Package Maintenance V17 starts from the exact green Unified Integration V16 branch head:

```text
a995ea59d95ddf4c72d7cbc6a08e746edf26e7c3
```

That V16 head passed CloudOS Native Full-System CI #420 and CloudOS CI Baseline #948 before V17 began. The V16 validation artifact digest is `sha256:657d19ca1a3e06896ad6df77021b4fd1cc00e1e3aab62fc450cce686f0358ffe`.

Current release architecture:

```text
CloudOS.Supervisor.exe V11
        |
        v
CloudOS.exe --supervised
        |
        +--> CloudOS.NativeRuntime.dll
        +--> Desktop / Taskbar / Start / Files / workspaces / control plane
        +--> Browser + Windows/WSL integration V16
        +--> explicit package maintenance V17
```

The release is built from `CloudOS.NativeShell.vcxproj`; `main_shell_v2.cpp` is the active shell entry point.

## Delivered milestones

| Version | Delivered capability | Automated evidence |
|---|---|---|
| V9 | fixed health ABI, Ready event, UI heartbeat, diagnostics/soak harness | contract + short hosted smoke |
| V10 | suspend/resume/display/WTS lifecycle revalidation and single-instance behavior | contract + deterministic lifecycle smoke |
| V11 | external `CloudOS.Supervisor.exe`, bounded restart, graceful exit and safe Explorer fallback decision | contract + real Ready/heartbeat supervisor smoke |
| V12 | event-driven idle behavior, cached paint and native surface/performance regression checks | contracts + surface tests + ~120 s idle soak |
| V13 | per-user transactional deployment, verified active version, repair, rollback, uninstall interlock foundations | contract + temp-directory deployment smoke |
| V14 | explicit per-user shell activation, exact previous-value snapshot/restore, journal repair and independent Explorer rollback | contract + HKCU sandbox activation smoke + real shell-entry Ready probe |
| V15 | repository/source-of-truth cleanup for humans and coding agents; central native contract suite | repository-clarity contract + full existing CI matrix |
| V16 | unified Windows + Linux/WSL integration: Browser destinations, app inventory, install/remove, WSLg discovery and Desktop integration | contract + non-mutating capability smoke + full V9–V14 regression matrix |
| V17 | explicit selected-app package maintenance through WinGet/apt/Snap/Flatpak with safe identity handling and visible Terminal execution | contract + non-mutating maintenance smoke + full regression matrix |

## Current ownership

- Native desktop UI: `desktop/CloudOS.NativeShell`.
- Low-level native ABI/runtime: `desktop/CloudOS.NativeRuntime`.
- External recovery/supervision: `desktop/CloudOS.NativeRecovery` -> `CloudOS.Supervisor.exe`.
- Cross-project supervisor protocol: `desktop/CloudOS.NativeCommon`.
- Windows + Linux discovery/install/remove boundary: `native_integration_v16.*`.
- Explicit selected-package upgrade boundary: `native_package_maintenance_v17.h`.
- Build/deployment/activation/test tooling: `scripts/native`.
- Current architecture/code map/validation: `docs/native`.

Read `AGENTS.md` and `docs/native/CODEMAP.md` before changing a subsystem.

## Production gates still open

The following remain distinct from hosted CI success:

| Area | Remaining gate |
|---|---|
| Real shell login | activate V14 in a disposable VM, perform logout/login cycles and verify recovery |
| Crash before Ready | force real pre-Ready crashes across logon and prove Supervisor/Explorer recovery |
| Reboot/boot recovery | reboot with activation enabled; verify emergency rollback independently of CloudOS UI |
| Physical lifecycle | real suspend/resume, RDP transport, user switching and monitor hotplug/DPI changes |
| Long soak | 24 h per target configuration, then multi-day pilot use |
| Multi-user | two accounts/two sessions with isolated state, IPC and recovery scope |
| Accessibility | Narrator/UIA, keyboard-only flows, IME, contrast, touch and 100–300% scaling |
| Release identity | production Authenticode signing and publisher/release-chain review |
| Security review | threat review of IPC, install/activation/package permissions and recovery boundaries |
| Installer UX | production-grade install/update channel UX beyond the current per-user transactional scripts |
| Real package lifecycle | manual/VM WinGet, apt, Snap and Flatpak install/update/remove matrices including UAC/sudo and failure paths |

Do not claim these gates passed without corresponding physical/VM evidence.

## Active shell activation model

V14 owns current activation through a per-user Winlogon `Shell` transaction. Hosted CI injects a dedicated HKCU sandbox subkey and deliberately leaves the production Winlogon key unchanged.

The old `scripts/native/configure-cloudos-shell-launcher.ps1` experiment is **LEGACY**. It targets Windows Shell Launcher/WESL on supported editions and is not the current production authority. Do not use it as a substitute for V13 + V14.

## Package integration model

V16 remains the discovery/install/remove authority. V17 adds only the deliberately separate **maintenance command boundary** used by the Apps UI.

V17 is user initiated. It does not run updates while loading the catalog, does not use `winget upgrade --all`, does not run blanket `apt upgrade`, and does not store sudo credentials. WinGet/UAC/sudo/package-manager output remains visible through the first-party Terminal.

## Build and validation

Canonical local flow:

```powershell
pwsh -NoProfile -File scripts/native/test-native-contract-suite.ps1
scripts\native\build-cloudos-native.cmd Release
```

The build itself invokes the same central contract suite, then produces and verifies:

- `CloudOS.exe`
- `CloudOS.NativeRuntime.dll`
- `CloudOS.Supervisor.exe`
- `cloudos-native-manifest.json`
- source fingerprint/build-head metadata

Full runtime validation belongs to `.github/workflows/cloudos-native-full-system.yml`.

## Rules for future milestones

1. Do not reintroduce React/WebView as Desktop authority; WebView2 remains scoped to the Browser.
2. Do not create competing watchdog/recovery authorities; Supervisor V11 remains external authority unless explicitly versioned.
3. Preserve exact rollback semantics for shell activation and transactional deployment.
4. Change ABI/protocol contracts only through explicit versioning.
5. Prefer behavior-preserving modularization over cosmetic file moves.
6. Keep package mutations explicit, reviewable and user initiated; do not hide UAC/sudo or add global auto-update as a shortcut.
7. Update `AGENTS.md`, `CODEMAP.md` and `VALIDATION.md` when source ownership or acceptance criteria change.
8. Every milestone must finish with actual Windows CI evidence before being called complete.
