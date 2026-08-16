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
| Linux desktop app discovery/launch | **real but command-oriented** | `backend/src/apps/appCatalog.js` invokes fixed `/bin/bash -lc` / `/bin/sh -lc` scripts through `wsl.exe`. It is not a generic guest-agent transport and is untouched here. |
| Host metrics | **real (Windows host only)** | `/api/system/metrics` reads host metrics. It does not expose guest `/proc` metrics. |
| Process Manager / System Center process model | **simulated** | Frontend kernel/process/service/driver/resource model is virtual and remains so. |
| WSL readiness | **partial** | Readiness observes WSL snapshot/version and WSLg availability, not a guest service handshake or guest process health. |
| Frontend/backend terminal authentication | **real** | Existing terminal WebSocket validates origin and a session token. |
| Native Host/backend lifecycle | **real** | Host supervisor already has bounded startup/health/shutdown and an authenticated private host lease. The new guest supervisor follows the same fail-closed lifecycle principles without sharing its credentials. |
| Persistence/database | **real** | Backend has a persistent database. The WSL-core foundation does not reference or open it. |
| Authenticated Linux guest agent | **absent** | Added by this branch. |
| Persistent Windows-to-guest data channel independent of `wsl.exe` | **absent** | Added by this branch after bootstrap, using WSL localhost forwarding. |
| Guest `/proc` / cgroup v2 metrics | **absent** | Added by this branch. |
| Opaque server-created Linux session IDs | **absent** | Added by this branch. |
| Session reconnect/takeover after transport loss | **absent by design in protocol v1** | Disconnect is fail-closed and kills owned sessions. |
| Simultaneous multi-distro channels | **absent in vertical v1** | Supervisor is one service/connection per selected WSL2 distribution; the protocol is distro-neutral. |
| systemd unit installation/enablement | **absent by design** | Foreground supervision is the portable fallback for this phase. |

## 2. Existing projects evaluated and reused

### Reused: `github.com/creack/pty` v1.1.24

Instead of implementing Linux PTY allocation, controlling-terminal setup and resize ioctls from scratch, `cloudos-core` uses the MIT-licensed `creack/pty` package for `StartWithSize` and `Setsize`.

- https://github.com/creack/pty
- https://pkg.go.dev/github.com/creack/pty@v1.1.24

### Evaluated, not selected for the first vertical

- `microsoft/go-winio`: useful Windows named-pipe and Hyper-V socket primitives, but Hyper-V sockets would still require a WSL-specific supported service-registration/addressing path that this audit did not prove. Adding it would expand the trusted transport surface without solving a current requirement.
- `prometheus/procfs`: mature `/proc` access, but basic read-only uptime/load/memory/process/cgroup metrics are small enough for this vertical and do not justify another large dependency yet.
- `albertony/npiperelay`, `mame/wsl2-ssh-agent` and related `socat` relays: proven examples of bridging Windows named pipes and WSL Unix sockets/stdin-stdout. They are useful precedent, but would add a Windows helper plus guest relay/package dependency to this phase. The vertical therefore does not copy their transport; it keeps them as a fallback design candidate if localhost forwarding proves unreliable on the target WSL configuration.
- Rust `std::process::Command`: technically suitable and safe with separate arguments, but Go offers a smaller integration step here because the chosen PTY library and single-binary service are direct fits.

## 3. Language decision: Go

Both Rust and Go support shell-free process spawning with separate executable/argument APIs. Go was selected for protocol v1 because:

1. `os/exec.CommandContext(name, args...)` does not invoke a system shell unless the program explicitly asks it to.
2. `creack/pty` supplies the PTY lifecycle and resize primitives needed now.
3. The service can remain a small foreground binary with standard-library TCP, JSON, HMAC and process supervision.
4. The first vertical does not need unsafe FFI or a custom Windows socket binding.

This is an integration/maintenance choice, not a latency or performance claim. The module requires Go 1.25+; CI uses a current supported Go toolchain.

References:
- https://pkg.go.dev/os/exec
- https://doc.rust-lang.org/stable/std/process/struct.Command.html

## 4. Service manager decision: foreground supervisor first

WSL supports systemd, but Microsoft documents that not every distribution necessarily uses it. Therefore protocol v1 does **not** enable, install, configure or depend on systemd. The Host launches a foreground `cloudos-core` only when the feature is explicitly enabled and bootstrap is explicitly authorized.

A later packaging phase may provide an optional systemd unit for distros already configured with systemd, but service activation must not become a prerequisite for other WSL2 distros.

Reference: https://learn.microsoft.com/windows/wsl/systemd

## 5. Transport decision

### Selected for v1: WSL localhost-forwarded loopback TCP

The Linux service binds only `127.0.0.1:0`. It reports the kernel-selected port over the bootstrap stdio channel. After that, the Windows Host connects to `127.0.0.1:<port>` and all session traffic leaves `wsl.exe`.

Microsoft documents that WSL2 forwards Linux guest ports to Windows localhost by default (`localhostForwarding=true`), and that Linux networking apps can be reached from Windows through localhost. This is the supported behavior used by the vertical slice. The implementation deliberately fails closed if that forwarding path is unavailable; it does not bind the guest service to every interface or create firewall/portproxy rules. Recent WSL issue reports show that localhost behavior can still vary with networking mode/build, so this transport remains **experimental until the target Windows/WSL machine passes the physical probe**.

References:
- https://learn.microsoft.com/windows/wsl/networking
- https://learn.microsoft.com/windows/wsl/wsl-config
- https://learn.microsoft.com/windows/dev-environment/wsl-interop

### Why AF_VSOCK was not selected

The Microsoft Hyper-V socket API is asymmetric: Windows uses `AF_HYPERV`, while a Linux guest uses `AF_VSOCK`, with Hyper-V VM/service addressing on the Windows side. That proves that a Windows `.NET` process cannot simply assume a Linux-style AF_VSOCK port contract. No supported, stable WSL application service-registration path was proven for this CloudOS process, so v1 does not depend on it.

Reference: https://learn.microsoft.com/windows-server/virtualization/hyper-v/make-integration-service

### Unix socket

A Unix domain socket remains a sensible future local endpoint inside the distro or for systemd socket activation. It is not the cross-boundary Windows transport in v1.

## 6. WSLg boundary

WSLg already has its own system distro, Weston/XWayland/PulseAudio/FreeRDP architecture and projects its communication sockets into user distributions. This branch does not intercept those sockets, replace Weston, embed WSLg surfaces or alter WSLg configuration.

Reference: https://github.com/microsoft/wslg

## 7. Protocol v1

Wire format:

```text
uint32 big-endian JSON byte length
UTF-8 JSON envelope
```

Limits:

- protocol version: `1`
- maximum frame: 1 MiB
- maximum I/O chunk: 64 KiB
- maximum concurrent sessions: 8
- maximum arguments: 64
- maximum argument size: 4096 bytes
- maximum requested environment entries: 16

Authentication:

1. Windows creates a random 32-byte bootstrap secret.
2. Secret is written to the initial `wsl.exe` child stdin; it is never placed in argv or environment.
3. Client sends `hello` + random nonce.
4. Server returns its nonce and HMAC-SHA256 proof bound to role `server`.
5. Client verifies it and returns a role-bound `client` proof.
6. Server generates an opaque connection identifier and sends `ready`.

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

- `session.output` with base64 bytes and `stdout`, `stderr` or `pty` stream
- `session.exit`

Protocol errors are sanitized stable codes. Raw paths, process output and internal exceptions are not inserted into logs automatically.

## 8. Process policy

The server accepts an executable and argument vector; it never accepts a shell command line. Protocol v1 intentionally allowlists only benign binaries used for foundation testing and basic identity:

- `/bin/cat`, `/bin/echo`, `/bin/sleep`
- `/usr/bin/cat`, `/usr/bin/echo`, `/usr/bin/id`, `/usr/bin/printf`, `/usr/bin/sleep`, `/usr/bin/uname`

No shell, Python, package manager or offensive Kali utility is allowlisted.

Child environment is built from scratch. Base values are `PATH`, `HOME`, `USER`, `LOGNAME`, `LANG`, and `TERM`. Client-requested overrides are restricted to terminal/locale display variables. JWT/token/password/credential variables are never inherited.

Working directory must be an existing absolute directory under the current user's home or `/tmp`. A requested user must equal the service user.

## 9. Metrics

Metrics are read-only observations from Linux kernel interfaces:

- `/proc/uptime`
- `/proc/loadavg`
- `/proc/meminfo`
- numeric `/proc/<pid>` directories
- `/proc/self/cgroup`
- cgroup v2 `memory.current`, `memory.max`, `pids.current`, and `cpu.stat` when exposed

No cgroup is created, moved, delegated or modified.

## 10. Lifecycle and failure semantics

- `wsl.exe` is retained only for distro discovery, service availability probe and foreground bootstrap.
- Once authenticated, request/session traffic uses the TCP channel.
- A single authenticated connection owns its opaque sessions.
- Disconnect kills all sessions owned by that connection and the transient service exits.
- Protocol v1 does not transfer sessions to a reconnecting client.
- Request, bootstrap and connection operations have bounded timeouts/cancellation.
- Host shutdown first asks the guest service to shut down; it only terminates the `wsl.exe` process it created if graceful exit times out.
- No `wsl --shutdown`, `--terminate`, install/import/update/default/version mutation or elevation is used by this foundation.

## 11. Feature boundary

The existing terminal remains the default. `CLOUDOS_WSL_CORE_FOUNDATION=1` is the explicit experimental feature flag, and the supervisor additionally requires `AllowBootstrap=true` from its caller. This branch does not reroute the current Terminal, System Center or Process Manager.

The physical probe is the only current vertical consumer:

```text
Windows probe
  -> WslCoreSupervisor
  -> wsl.exe (probe/bootstrap only)
  -> cloudos-core
  -> authenticated localhost channel
  -> /bin/echo session
  -> /proc + cgroup metrics
  -> PTY /bin/cat + resize/input
  -> signal + exit
  -> zero active sessions
  -> shutdown
```

## 12. Physical validation safety

`scripts/validate-wsl-core-foundation.ps1`:

- selects an already-installed WSL2 distro;
- never installs/imports/updates/terminates/configures WSL;
- never elevates;
- builds only into unique temporary caches/paths using an already-present Go toolchain (inside WSL or Windows), downloading Go module/toolchain data only into those temporary caches when Go's normal toolchain mechanism needs it;
- runs the Windows probe;
- removes only its own temporary binary/cache paths;
- does not open the CloudOS database.

If neither Windows nor the selected WSL distribution already has a usable Go command, validation fails with `GO_NOT_FOUND`; it does not install one.
