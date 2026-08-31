# CloudOS architecture — compatibility reference

> **Compatibility document.** The current desktop product is the C++/Win32 **CloudOS Native Shell**. Its authoritative architecture lives in [`docs/native/ARCHITECTURE.md`](native/ARCHITECTURE.md), with task-to-file ownership in [`docs/native/CODEMAP.md`](native/CODEMAP.md).

This file exists so older React/WPF/Node material can remain understandable without being mistaken for the current desktop authority.

## Current product authority

```text
CloudOS.Supervisor.exe
        |
        v
CloudOS.exe --supervised
        |
        +--> CloudOS.NativeRuntime.dll
        +--> Win32/DWM/Shell APIs
        +--> WebView2 only inside the native Browser surface
```

The current native compile graph is defined by:

```text
desktop/CloudOS.NativeShell/CloudOS.NativeShell.vcxproj
```

The current shell entry point is `desktop/CloudOS.NativeShell/src/main_shell_v2.cpp`.

V13 owns transactional per-user deployment. V14 owns explicit per-user shell activation and exact rollback of the prior `Shell` value. `CloudOS.Supervisor.exe` V11 remains the external readiness/heartbeat/recovery authority.

## Compatibility / historical stack

The repository still contains `frontend/`, `backend/`, `desktop/CloudOS.Host`, Bootstrap/Browser test infrastructure and other React/WPF/Node-era components. They can remain useful for compatibility, experiments and regression coverage, but they do **not** define the native Desktop, Taskbar, Start menu, Files shell or recovery path.

Older architecture descriptions may mention:

```text
CloudOS.Host (WPF/WebView2)
React/Vite/Zustand desktop
Node/Express local agent
HTTP/WebSocket bridge
```

Treat that model as **compatibilidade/histórico**, not as the source of truth for current native-shell changes.

## Where to read next

1. [`native/ARCHITECTURE.md`](native/ARCHITECTURE.md) — current process and subsystem architecture.
2. [`native/CODEMAP.md`](native/CODEMAP.md) — exact files for each native feature.
3. [`native/VALIDATION.md`](native/VALIDATION.md) — structural contracts, runtime smokes and physical-test limits.
4. [`native/DESKTOP_SYSTEM_ROADMAP.md`](native/DESKTOP_SYSTEM_ROADMAP.md) — delivered milestones and remaining production gates.
5. [`../AGENTS.md`](../AGENTS.md) — rules for humans and coding agents entering the repository.

If this file and `docs/native/*` disagree about the current desktop, `docs/native/*`, the `.vcxproj` compile graph and green Full-System CI evidence take precedence.
