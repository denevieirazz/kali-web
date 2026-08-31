# CloudOS.NativeRuntime

`CloudOS.NativeRuntime` is the low-level C++/Win32 runtime DLL used by the native shell. It is **not** the desktop UI and it is not a bridge to React, Node, WPF or a managed host.

Release output:

```text
CloudOS.NativeRuntime.dll
```

## Source of truth

- `CloudOS.NativeRuntime.vcxproj` — compiled graph and build policy.
- `include/cloudos_native_runtime.h` — small versioned C ABI consumed by `CloudOS.exe`.
- `src/` — runtime implementation.

The shell validates runtime ABI compatibility during startup. An incompatible runtime must fail closed rather than continue with an unknown ABI.

## Responsibilities

- process creation/ownership using Win32 and Job Objects;
- ConPTY creation, I/O and resize;
- WinEvent/HWND discovery and window metadata;
- focus/layout helpers used by the native shell;
- WSL platform integration where available.

## Boundary

Do not put Desktop/Taskbar/Start UI policy here. Those belong to `CloudOS.NativeShell`. Do not put Supervisor V11 policy here; that belongs to `CloudOS.NativeRecovery` with cross-process constants in `CloudOS.NativeCommon`.

The runtime does not attempt to bypass Secure Desktop/UAC, UIPI, protected windows, DRM, anti-cheat, AppContainer or other Windows security boundaries.
