# CloudOS.NativeRuntime

Native Windows engine for CloudOS.

This project is intentionally introduced beside the existing .NET/WPF Host instead of replacing it in one rewrite. The migration boundary is a small C ABI so the high-level CloudOS bridge can remain stable while low-level Windows ownership moves to C++.

## Phase 1 responsibilities

- CreateProcessW in suspended state.
- Kill-on-close Job Object ownership.
- Resume the primary thread only after CloudOS installs its capability.
- Enumerate the complete Job process tree.
- Terminate the Job as one containment unit.

The current C# implementation remains as an automatic fallback when the native DLL is unavailable. Set `CLOUDOS_NATIVE_RUNTIME=managed` to force the fallback, or `CLOUDOS_NATIVE_RUNTIME=cpp` to require this runtime and fail closed when it cannot be loaded.

## Planned migration

1. process and Job ownership
2. HWND discovery and lifecycle
3. input routing
4. Windows.Graphics.Capture / D3D11
5. DirectComposition presenter
6. WebView2 CompositionController host

The public frontend bridge should not need to change as these layers move.
