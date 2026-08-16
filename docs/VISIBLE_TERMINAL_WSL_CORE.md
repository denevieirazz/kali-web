# Visible CloudOS Terminal over WSL Core v2

Base: `feature/cloudos-wsl-core-secure-terminal` at `7424eb7c8775bb534f05ff0c7efedbc55a50e551`.

This phase does not alter the validated Go daemon, AES-GCM protocol, .NET probe, Node WSL-core adapter, Browser, System Center, Process Manager, Kali Tool Center, WSL configuration, or CloudOS real database.

The existing `CloudOS Terminal` React/xterm application remains the only visible Terminal workspace. For WSL tabs the transport is:

`xterm.js -> authenticated /ws/terminal -> websocket.js -> wslCoreAdapter.js -> protected protocol v2 -> cloudos-core -> /bin/bash -l`.

The frontend does not declare success when the WebSocket itself opens. It stays `connecting` until the backend sends a `backend` message. WSL Core mode additionally requires `protocol=2` and `protection=aes-256-gcm-seq`. An explicitly authorized legacy backend is rendered as `legacy-fallback`; it is never displayed as WSL Core v2.

User input is forwarded exactly. The only special lifecycle key is the exact xterm Ctrl+C byte (`0x03`), which is converted into the existing `signal: interrupt` WebSocket operation. Pasted text is never suffixed with Enter/newline.

Resize events before backend readiness are coalesced to the latest terminal dimensions and flushed after readiness. Component teardown removes xterm subscriptions, ResizeObserver and WebSocket listeners, sends close when possible, closes the socket and disposes xterm.

The footer exposes only distribution, transport mode and user-facing connection state. It deliberately omits cloudos-core port, PID, bootstrap diagnostics, nonce and secret material.

## Feature flags

Development/physical launch uses child-process-scoped environment only:

- `CLOUDOS_WSL_CORE_FOUNDATION=1`
- `CLOUDOS_WSL_CORE_TERMINAL=1`
- `CLOUDOS_WSL_CORE_LINUX_PATH=<temporary validated binary>`
- `CLOUDOS_WSL_CORE_TERMINAL_FALLBACK=0` by default

Safe development launcher:

```powershell
pwsh -NoLogo -NoProfile -File scripts/start-cloudos-visible-terminal-v2.ps1
```

It builds a temporary Linux core, uses an isolated temporary CloudOS data/runtime directory and never edits persistent environment variables or WSL configuration. `-AllowLegacyFallback` must be explicitly supplied to enable the old PTY fallback.

Physical validation uses a fresh isolated account/database, opens the existing visible CloudOS Terminal in Edge via Playwright, confirms `wsl-core-v2`, runs only `uname -a`, `pwd`, `id` and benign `sleep`, verifies Ctrl+C, window resize, close with a process active and absence of tracked Linux orphans. It fingerprints real CloudOS data directories and WSL distro configuration before/after.
