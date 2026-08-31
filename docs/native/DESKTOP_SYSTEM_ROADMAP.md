# CloudOS Native Desktop — delivery roadmap

This roadmap describes the **current C++/Win32 native product**. Historical React/WPF/Node plans are compatibility material and do not override this document.

## Current validated baseline

Unified Start/Search V17 starts from the exact green Unified Integration V16 branch head:

```text
a995ea59d95ddf4c72d7cbc6a08e746edf26e7c3
```

That V16 head passed:

- CloudOS CI Baseline #948 — run `33399404466`;
- CloudOS Native Full-System CI #420 — run `33399404475`;
- verified artifact digest `sha256:657d19ca1a3e06896ad6df77021b4fd1cc00e1e3aab62fc450cce686f0358ffe`.

V17 work must not rewrite that validated base or merge into `main` as a side effect of validation.

Current release architecture:

```text
CloudOS.Supervisor.exe V11
        |
        v
CloudOS.exe --supervised
        |
        +--> CloudOS.NativeRuntime.dll
        +--> Desktop / Taskbar / Start / Files / workspaces / control plane
        +--> NativeIntegrationV16 Windows + Linux/WSL boundary
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
| V16 | Browser→Files download destination, unified Windows/WSL app inventory, WinGet/apt/snap/flatpak boundary, Linux Desktop launchers and event-driven install discovery | V16 contract + non-mutating hosted smoke + complete V9–V14 regression matrix |

## Active milestone — V17 Unified Start/Search

V17 closes the remaining discovery gap after V16: Linux GUI applications must participate directly in Start/Search without creating a second Linux inventory.

Design:

- `NativeIntegrationV16::EnumerateLinuxGuiApps()` remains the Linux discovery authority;
- `native_integration_v16_launchers.h` owns the shared managed `.lnk` adapter used by Desktop and Start;
- `NativeStartIndex` consumes V16 Linux entries alongside Start folders and `shell:AppsFolder`;
- Linux entries receive app-first search ranking and a visible `Linux`/distro identity;
- WSL application-directory change notifications refresh Desktop and Start independently, with no polling timer;
- Start itself must not construct `wsl.exe`/`gtk-launch` commands;
- all V9–V16 safety/performance/deployment/activation gates remain mandatory.

Acceptance before V17 may be called complete:

1. central native contract suite includes V17;
2. native Release x64 builds under existing `/W4 /WX` policy;
3. V17 non-mutating smoke passes and Supervisor self-test remains green;
4. production HKCU Winlogon remains unchanged;
5. Full-System V9–V17 matrix passes on Windows CI;
6. Baseline CI passes;
7. verified release artifact is published and independently inspected;
8. validation PR remains isolated from `main` unless an explicit merge is requested.

Hosted CI with no configured WSL distro cannot prove a real WSLg GUI launch. That remains a VM/manual gate.

## Current ownership

- Native desktop UI: `desktop/CloudOS.NativeShell`.
- Low-level native ABI/runtime: `desktop/CloudOS.NativeRuntime`.
- External recovery/supervision: `desktop/CloudOS.NativeRecovery` -> `CloudOS.Supervisor.exe`.
- Cross-project supervisor protocol: `desktop/CloudOS.NativeCommon`.
- Windows+Linux discovery/package boundary: `desktop/CloudOS.NativeShell/src/native_integration_v16.*`.
- Shared managed Linux launch adapter: `desktop/CloudOS.NativeShell/src/native_integration_v16_launchers.h`.
- Unified Start/Search index: `desktop/CloudOS.NativeShell/src/native_start_index.*`.
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
| Real WSLg | configured distro(s), Linux GUI install/remove, Start/Desktop notification and actual GUI launch |
| Long soak | 24 h per target configuration, then multi-day pilot use |
| Multi-user | two accounts/two sessions with isolated state, IPC and recovery scope |
| Accessibility | Narrator/UIA, keyboard-only flows, IME, contrast, touch and 100–300% scaling |
| Release identity | production Authenticode signing and publisher/release-chain review |
| Security review | threat review of IPC, install/activation permissions and recovery boundaries |
| Installer UX | production-grade install/update channel UX beyond the current per-user transactional scripts |

Do not claim these gates passed without corresponding physical/VM evidence.

## Active shell activation model

V14 owns current activation through a per-user Winlogon `Shell` transaction. Hosted CI injects a dedicated HKCU sandbox subkey and deliberately leaves the production Winlogon key unchanged.

The old `scripts/native/configure-cloudos-shell-launcher.ps1` experiment is **LEGACY**. It targets Windows Shell Launcher/WESL on supported editions and is not the current production authority. Do not use it as a substitute for V13 + V14.

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
5. Keep Windows↔Linux discovery/command construction inside `NativeIntegrationV16`; consumers must not fork a second catalog.
6. Prefer behavior-preserving modularization over cosmetic file moves.
7. Update `AGENTS.md`, `CODEMAP.md` and `VALIDATION.md` when source ownership or acceptance criteria change.
8. Every milestone must finish with actual Windows CI evidence before being called complete.
