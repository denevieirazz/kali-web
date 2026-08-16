# CloudOS WSL2 Core Foundation

Base audited: `integration/cloudos-validated-features` at `56f0ca8bc0a59987a43295da1ded277afc40e6e9`.

This foundation is intentionally experimental and additive. It does not modify Browser code, install or reconfigure WSL, enable systemd, touch WSLg, provision a distribution, or migrate the current Terminal/System Center.

## 1. Audit of the current WSL path

| Area | State before this branch | Evidence / consequence |
|---|---|---|
| WSL distribution discovery/version/default/preferred | **real** | `backend/src/wsl/distroService.js` calls `wsl.exe` with argument arrays and parses `--list --verbose` / `--version`. |
| WSL install/update/set-version/terminate/default mutations | **real** | Existing WSL routes and `scripts/cloudos-wsl-broker.ps1` can mutate WSL and may elevate. Those paths are deliberately not reused by `cloudos-core`. |
| WSL terminal PTY | **partial** | `backend/src/terminal/websocket.js` uses Windows `node-pty` around `wsl.exe -d <distro> -- /bin/bash -l`. I/O still traverses `wsl.exe`; no guest service or server-owned Linux session exists. |
| Terminal when `node-pty` is unavailable | **simulated** | Existing WebSocket terminal falls back to a local echo emulator. |
| Linux desktop app discovery/launch | **real but command-oriented** | `backend/src/apps/appCatalog.js` invokes fixed shell scripts through `wsl.exe`; this is not reused as the guest-agent transport. |
| Host metrics | **real (Windows host only)** | `/api/system/metrics` reads host metrics, not guest `/proc`. |
| Process Manager / System Center process model | **simulated** | The frontend kernel/process/service/driver/resource model is virtual and remains unchanged. |
| WSL readiness | **partial** | Existing readiness checks WSL inventory/version/WSLg, not an authenticated guest service. |
| Frontend/backend terminal authentication | **real** | Existing terminal WebSocket validates origin and a session token. |
| Native Host/backend lifecycle | **real** | The Host already has bounded startup/health/shutdown and a private authenticated host lease. |
| Persistence/database | **real** | Backend persistence exists; this foundation does not reference or open it. |
| Authenticated Linux guest agent | **absent** | Added by this branch. |
| Persistent Windows-to-guest data channel independent of `wsl.exe` | **absent** | Added by this branch after bootstrap. |
| Guest `/proc` / cgroup v2 metrics | **absent** | Added by this branch. |
| Opaque server-created Linux session IDs | **absent** | Added by this branch. |
| Session reconnect/takeover | **absent by design in v1** | Disconnect is fail-closed and kills owned sessions. |
| Simultaneous multi-distro channels | **absent in vertical v1** | One supervisor/service connection is used per selected WSL2 distro. |
| systemd unit installation/enablement | **absent by design** | Foreground supervision is the portable v1 fallback. |

## 2. Existing projects evaluated and reused

### Reused: `github.com/creack/pty` v1.1.24

`cloudos-core` reuses the MIT-licensed `creack/pty` package for Linux PTY allocation, controlling-terminal setup and resize (`StartWithSize` / `Setsize`) instead of reimplementing those primitives.

References:
- https://github.com/creack/pty
- https://pkg.go.dev/github.com/creack/pty@v1.1.24

### Evaluated, not selected for this vertical

- `microsoft/go-winio`: useful named-pipe / Hyper-V socket primitives, but a supported no-admin WSL service-registration/addressing path was not proven for this application.
- `prometheus/procfs`: mature `/proc` library, but the first read-only metric set is intentionally small and direct.
- `albertony/npiperelay`, `mame/wsl2-ssh-agent`, and `socat` relay patterns: useful precedent for pipe/socket bridging, but they add extra helper/package dependencies. They remain fallback candidates if localhost forwarding proves unreliable on the target machine.
- Rust `std::process::Command`: technically suitable; Go was selected because the PTY dependency and single-binary service fit this vertical with less integration surface.

## 3. Language decision: Go

Both Rust and Go support process creation with an executable plus separate arguments. Go is used for protocol v1 because:

1. `os/exec.CommandContext(name, args...)` keeps the argument vector separate and does not invoke a shell unless one is explicitly selected.
2. `creack/pty` supplies the PTY lifecycle required by the vertical.
3. TCP, JSON, HMAC and process supervision are available with a small standard-library surface.
4. No unsafe FFI or custom Windows socket binding is required for the chosen transport.

This is an integration/maintenance choice, not a latency claim. The module declares **Go 1.23+**, and CI validates it with Go 1.23.x.

References:
- https://pkg.go.dev/os/exec
- https://doc.rust-lang.org/stable/std/process/struct.Command.html

## 4. Service manager decision

Protocol v1 does not enable, install, configure or require systemd. The Windows supervisor starts a foreground `cloudos-core` only when the feature flag is enabled and bootstrap is explicitly authorized.

A later packaging phase may add an optional systemd unit for distributions that already use systemd. Service activation must not become a prerequisite for other WSL2 distributions.

Reference: https://learn.microsoft.com/windows/wsl/systemd

## 5. Transport decision

### Selected for v1: WSL localhost-forwarded loopback TCP

The Linux service binds only `127.0.0.1:0`. It reports the kernel-selected port over bootstrap stdio. Windows then connects to `127.0.0.1:<port>`, and normal session traffic no longer traverses `wsl.exe`.

This relies on WSL2 localhost forwarding. The implementation fails closed if the path is unavailable; it does not bind to all guest interfaces, create firewall rules, or create portproxy rules. Physical validation on the target Windows/WSL installation remains mandatory before this transport is treated as production-ready.

References:
- https://learn.microsoft.com/windows/wsl/networking
- https://learn.microsoft.com/windows/wsl/wsl-config
- https://learn.microsoft.com/windows/dev-environment/wsl-interop

### Why AF_VSOCK / Hyper-V sockets were not selected

The Windows side uses Hyper-V socket semantics while Linux guests use VSOCK semantics, and a supported WSL application registration/addressing path that satisfies the no-elevation/no-host-mutation requirement was not proven. Protocol v1 therefore does not depend on it.

Reference: https://learn.microsoft.com/windows-server/virtualization/hyper-v/make-integration-service

### Unix socket

A Unix domain socket remains a future internal guest endpoint or systemd socket-activation option. It is not the Windows-to-WSL boundary transport in v1.

## 6. WSLg boundary

WSLg already has its own system distro and Weston/XWayland/audio/RDP integration architecture. This branch does not intercept WSLg sockets, replace Weston, embed WSLg surfaces or alter WSLg configuration.

Reference: https://github.com/microsoft/wslg

## 7. Protocol v1

Wire format:

```text
uint32 big-endian JSON byte length
UTF-8 JSON envelope
```

Limits:
- version: `1`
- frame: 1 MiB
- I/O chunk: 64 KiB
- concurrent sessions: 8
- arguments: 64
- argument size: 4096 bytes
- requested environment entries: 16

Authentication:
1. Windows creates a random 32-byte bootstrap secret.
2. The secret is written to the initial `wsl.exe` child stdin, never argv/environment.
3. Client sends `hello` plus a random nonce.
4. Server sends its nonce plus a role-bound HMAC-SHA256 server proof.
5. Client verifies it and sends a role-bound client proof.
6. Server creates an opaque connection identifier and sends `ready`.

No JWT, Host lease token, browser nonce or backend secret is reused.

Requests:
- `health`
- `metrics.get`
- `session.create`
- `session.input`
- `session.resize`
- `session.signal`
- `session.status`
- `session.wait`
- `shutdown`

Events:
- `session.output` (`stdout`, `stderr`, or `pty`, base64 bytes)
- `session.exit`

Errors use sanitized stable codes.

## 8. Process policy

The guest accepts an executable and argument vector; it never accepts a shell command line. The v1 allowlist is deliberately benign:

- `/bin/cat`, `/bin/echo`, `/bin/sleep`
- `/usr/bin/cat`, `/usr/bin/echo`, `/usr/bin/id`, `/usr/bin/printf`, `/usr/bin/sleep`, `/usr/bin/uname`

No shell, Python, package manager or offensive Kali tool is allowlisted.

The child environment is rebuilt from a minimal base (`PATH`, `HOME`, `USER`, `LOGNAME`, `LANG`, `TERM`). Requested overrides are limited to locale/terminal display variables; internal secrets/tokens are never inherited.

A requested working directory must be an existing absolute directory under the service user's home or `/tmp`. A requested user must match the service user.

## 9. Metrics

Read-only Linux observations:
- `/proc/uptime`
- `/proc/loadavg`
- `/proc/meminfo`
- numeric `/proc/<pid>` directories
- `/proc/self/cgroup`
- cgroup v2 `memory.current`, `memory.max`, `pids.current`, and `cpu.stat` when exposed

The implementation does not create, move, delegate or modify cgroups.

## 10. Lifecycle and failure semantics

- `wsl.exe` remains only for inventory, executable availability probing, and foreground bootstrap.
- Authenticated session traffic uses the TCP channel.
- One authenticated connection owns its opaque sessions.
- Disconnect kills sessions owned by that connection and the transient service exits.
- v1 has no reconnect/session takeover.
- Bootstrap, request and connection operations have bounded timeout/cancellation paths.
- Shutdown asks the guest to stop first; the supervisor only kills the exact `wsl.exe` child it created if graceful exit times out.
- This foundation never invokes `wsl --shutdown`, `--terminate`, install/import/update/default/version mutation, or elevation.

## 11. Feature boundary

The existing Terminal remains the default. `CLOUDOS_WSL_CORE_FOUNDATION=1` is the explicit experimental feature flag, and `AllowBootstrap=true` is also required from the caller. This branch does not reroute Terminal, System Center or Process Manager.

Vertical proof path:

```text
Windows probe
  -> WslCoreSupervisor
  -> wsl.exe (inventory/probe/bootstrap only)
  -> cloudos-core
  -> authenticated localhost channel
  -> benign Linux process + stdout/stderr
  -> real /proc + read-only cgroup metrics
  -> PTY input/resize
  -> signal + exit
  -> zero active sessions
  -> shutdown
  -> no orphan PID verification
```

## 12. Physical validation safety

`scripts/validate-wsl-core-foundation.ps1`:

- selects an already-installed WSL2 distro;
- never installs/imports/updates/terminates/configures WSL;
- never elevates;
- builds only into unique temporary paths/caches using an already-present Go 1.23+ toolchain on Windows or in WSL;
- runs the .NET physical probe;
- checks a database canary path remains untouched;
- verifies guest child/core PIDs are gone after shutdown;
- removes only its own temporary binary/cache paths.

If no usable Go command exists, validation fails with `GO_NOT_FOUND`; it does not install Go.
