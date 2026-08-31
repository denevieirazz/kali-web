# CloudOS V20 — Flutter ↔ Native C++ Bridge Integration

## 1. Overview
CloudOS V20 transitions the Flutter user interface from a pure visual presentation preview (V19) to a fully connected, typed bridge with the real CloudOS native C++ core and host operating system.

```
+-------------------------------------------------------------------+
|                           Flutter UI                              |
|   (Desktop, Taskbar, Start/Search, Files, Quick Settings, etc.)   |
+-------------------------------------------------------------------+
                                 |
                                 v
+-------------------------------------------------------------------+
|                      CloudOSBridge (Dart)                         |
|   - loadApps()                                                    |
|   - loadSystemSnapshot()                                          |
|   - launchApp(id)                                                 |
|   - setVolume(val) / setBrightness(val)                           |
|   - Full preview fallback on MissingPluginException               |
+-------------------------------------------------------------------+
                                 |
                     MethodChannel "cloudos/native/v19"
                                 v
+-------------------------------------------------------------------+
|               CloudOSFlutterBridgeV20 (Native C++)                |
|   - Registered with Flutter BinaryMessenger                       |
|   - Type-safe dispatch and strict argument validation             |
|   - Zero arbitrary command line execution from Dart               |
+-------------------------------------------------------------------+
                                 |
       +-------------------------+-------------------------+
       |                                                   |
       v                                                   v
+-----------------------------+             +-----------------------------+
|    Windows Native Core      |             |   WSLg / Linux Integration  |
| - Registry & Start Catalog  |             | - NativeIntegrationV16      |
| - ShellExecuteEx (Typed ID) |             | - WSL Distribution queries  |
| - System Power & Network    |             | - Typed GUI App Launch      |
+-----------------------------+             +-----------------------------+
```

---

## 2. Core Architectural Principles & Authorities

1. **Flutter is Pure Presentation and Consumer**:
   - Flutter widgets and Dart classes NEVER call `powershell.exe`, `wsl.exe`, `winget.exe`, `reg.exe`, or Win32 COM APIs directly.
   - All host interactions pass through the typed `CloudOSBridge` boundary.

2. **Preserved Core Authorities**:
   - **V9 Health**: Native health diagnostic checks.
   - **V10 Lifecycle**: Clean startup, shutdown, and error recovery.
   - **V11 Supervisor**: Fault-tolerant process supervisor.
   - **V12 Performance**: Sub-second startup and low idle CPU footprint.
   - **V13 Deployment**: Safe non-invasive deployment topology.
   - **V14 Shell Activation**: Isolated Winlogon / Explorer boundaries (never tampered with in V20).
   - **V16 NativeIntegration**: Source of truth for Windows and Linux GUI application enumeration and WSL discovery.
   - **V17 NativeStartIndex**: Indexing and query resolution for Start and universal search.

3. **Defensive Security Boundary**:
   - Dart sends only structured, typed identifiers (e.g. `windows:notepad`, `wsl:gimp`, `cloudos:files`).
   - C++ resolves the ID to trusted binary paths and executes via `ShellExecuteExW` or verified `wsl.exe` invocations.
   - Arbitrary command injection (`executeCommand("...")` or shell scripts) is strictly rejected and absent from the API contract.

4. **Robust Preview Fallback**:
   - In headless environments, CI widget tests, or standalone Flutter runs where the native plugin host is absent, `CloudOSBridge` catches `MissingPluginException` and falls back cleanly to static fixtures (`previewApps` and `previewSnapshot`).

---

## 3. MethodChannel Contract (`cloudos/native/v19`)

### Methods

| Method | Arguments | Returns | Description |
| :--- | :--- | :--- | :--- |
| `getApps` | None | `List<Map<String, Object?>>` | Enumerates unified app catalog (CloudOS, Windows, Linux/WSLg). |
| `getSystemSnapshot` | None | `Map<String, Object?>` | Returns device name, network status, battery %, volume, brightness, WSL status and distros. |
| `launchApp` | `{"id": String}` | `bool` | Resolves app ID to trusted target and launches process. |
| `setVolume` | `{"value": double}` | `bool` | Adjusts master system audio level (0.0 to 1.0). |
| `setBrightness` | `{"value": double}` | `bool` | Adjusts display brightness (0.0 to 1.0). |
| `getBridgeInfo` | None | `Map<String, Object?>` | Returns bridge metadata (schema: 20, version: "v20", bridge_type: "CloudOSFlutterBridgeV20"). |

---

## 4. Threading & Performance

- MethodChannel invocations are handled on the Flutter engine platform thread.
- Heavy discovery scans (such as Registry enumeration and WSL distribution enumeration) are cached in `CloudOSFlutterBridgeV20` with thread-safe `std::mutex` synchronization.
- Zero per-frame polling in Dart.
