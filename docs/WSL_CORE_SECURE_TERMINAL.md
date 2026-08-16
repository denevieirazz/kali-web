# CloudOS WSL Core Secure Terminal

Base: `feature/cloudos-wsl-core-foundation` at `e72a1abe573bb0e41eea410b235cb78da53e8a26`.

This phase is experimental and additive. It does not modify Browser code, WSL configuration, WSLg, installed distributions, or CloudOS database state.

## Protected protocol v2

Protocol v2 keeps the existing length-prefixed JSON handshake but moves every post-proof frame into an authenticated encrypted channel.

Handshake:

1. Windows/Node client sends plaintext `hello` with a random 32-byte client nonce.
2. `cloudos-core` returns a random 32-byte server nonce plus role-bound HMAC-SHA256 proof.
3. Client verifies the server proof and returns the client proof.
4. Both sides derive directional material from the bootstrap secret plus both nonces.
5. The first protected server-to-client frame is `ready`.
6. No request, response or event after client proof is sent in plaintext.

Key schedule:

- HKDF-SHA256 style extract/expand implemented with HMAC-SHA256.
- independent 256-bit AES keys for `client -> server` and `server -> client`;
- independent four-byte nonce prefixes per direction;
- nonce = direction prefix + uint64 big-endian sequence;
- AAD binds protocol v2, direction and sequence.

Protected frame:

```text
uint32 big-endian protected-body length
uint64 big-endian sequence
AES-256-GCM ciphertext
16-byte GCM authentication tag
```

Each direction starts at sequence `1` and accepts exactly the next expected value. Duplicate, replayed, skipped or reordered frames fail closed. Ciphertext/tag/AAD changes fail GCM authentication. Sequence changes fail either the exact sequence guard or GCM authentication.

The bootstrap secret is still delivered only through the initial `wsl.exe` child stdin and is never put in argv/environment.

## One real Terminal session

The generic `session.create` executable allowlist remains unchanged and still does **not** contain Bash, a package manager, Python or offensive Kali tools.

A separate method was added:

```text
terminal.create { rows, cols }
```

It accepts only terminal dimensions. The Linux service internally pins the process to:

```text
/bin/bash -l
```

The caller cannot provide executable, arguments, cwd, user or environment through `terminal.create`. Only one fixed Terminal session is permitted per authenticated core connection.

The existing browser-facing Terminal WebSocket now has two explicit feature flags:

- `CLOUDOS_WSL_CORE_TERMINAL=1` — attempt the new protected `cloudos-core` Terminal backend for the WSL profile.
- `CLOUDOS_WSL_CORE_TERMINAL_FALLBACK=1` — if and only if explicitly enabled, a failed WSL-core start may fall back to the existing node-pty path.

The foundation flag is still required:

- `CLOUDOS_WSL_CORE_FOUNDATION=1`

The temporary/packaged Linux core path is supplied through:

- `CLOUDOS_WSL_CORE_LINUX_PATH=/absolute/linux/path/to/cloudos-core`

Without the Terminal feature flag, behavior remains legacy. With the Terminal flag enabled and fallback disabled, core startup failure is fail-closed rather than silently switching implementations.

## Lifecycle

The integrated Terminal covers:

- create;
- input;
- asynchronous output events;
- resize;
- signal;
- exit;
- browser WebSocket disconnect;
- core-channel disconnect;
- shutdown;
- owner cleanup;
- parent-death cleanup.

PTY signals are sent to the PTY process group, not only the login-shell PID, so interrupt/close semantics reach the foreground process tree and cleanup is less likely to leave descendants behind.

The Node adapter destroys only the loopback socket and exact `wsl.exe` bootstrap child that it created. It never executes `wsl --terminate`, `wsl --shutdown`, install/import/update/version/default mutations, firewall rules or elevation.

## Safety boundaries

- generic executable allowlist remains benign and shell-free;
- no offensive tool was added to the allowlist;
- no Browser files are touched;
- no database API/path is used by the adapter or core;
- no WSL configuration is modified;
- WSLg is untouched;
- localhost forwarding remains the cross-boundary transport;
- the legacy Terminal backend remains available only according to the explicit feature/fallback flags above.

## Validation

Automated CI covers:

- Go protocol v2 tamper/replay/out-of-order tests;
- Go protected server handshake and request lifecycle;
- fixed Terminal creator and generic-shell denial;
- .NET AES-GCM protocol contracts;
- Node AES-GCM adapter tamper/replay/out-of-order tests;
- feature-flag fallback contract;
- static no-WSL-mutation/no-Browser/no-database/no-offensive-tool boundaries;
- builds of the Linux core, .NET client and physical probe.

Physical validation is performed with:

```powershell
pwsh -NoLogo -NoProfile -File scripts/validate-wsl-core-secure-terminal.ps1
```

The physical harness builds a temporary Linux core, runs the .NET vertical probe, runs the exact Node Terminal adapter against an installed WSL2 distro, verifies zero surviving tracked guest PIDs, checks a database canary, and removes only its owned temporary paths.

## Current limitations

- transport still depends on WSL2 localhost forwarding;
- protocol v2 has no reconnect/session takeover;
- one core connection owns one dedicated interactive Terminal session;
- the Node backend and .NET probe each create their own transient core connection during validation;
- `/bin/bash` must exist for the dedicated interactive Terminal method;
- there is no systemd packaging/service activation in this phase;
- this phase integrates one Terminal backend only; Process Manager/System Center are not migrated;
- legacy fallback is explicit but remains the previous `wsl.exe` + node-pty architecture when used.
