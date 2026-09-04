# Legacy React desktop — retired

The React/Vite CloudOS desktop was retired from the active repository surface on 2026-09-04.

The current presentation client is:

- `desktop/CloudOS.FlutterShell/` — Flutter presentation and Windows native bridge.

The current Windows authorities remain native:

- `desktop/CloudOS.NativeShell/` — `CloudOS.exe` shell/core authority;
- `desktop/CloudOS.NativeRuntime/` — native runtime;
- `desktop/CloudOS.NativeRecovery/` — Supervisor/recovery;
- `desktop/CloudOS.SystemBroker/` — typed system broker used by Flutter.

This directory intentionally keeps only package/lock metadata required by older repository history/tooling boundaries. The old React source tree, Vite entrypoint, web server, public assets and frontend tests are removed and must not be restored as a CloudOS desktop implementation.

WebView2 remains allowed only for the CloudOS Browser feature; it is not a desktop renderer.
