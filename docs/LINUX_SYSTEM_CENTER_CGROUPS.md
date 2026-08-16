# CloudOS Linux System Center + cgroups v2 foundation

Base: `integration/cloudos-validated-features` at `2d3380ba562d23e05947f81cc9581e8fe9bcfdbc`.

## Scope

This branch keeps the existing `task-manager` / System Center UI and adds a real Linux source through the already approved WSL Core v2 protected channel. The CloudOS virtual model remains an explicit separate source, and host Windows metrics remain a third separate source. Linux PIDs are never merged with virtual PIDs.

The approved visible Terminal transport, `backend/src/terminal/wslCoreAdapter.js`, the protocol crypto implementation, Browser, database implementation, and WSL configuration are not changed.

## Protected RPCs

The daemon adds version-2 protected RPCs `process.list`, `process.get`, `process.signal`, `system.metrics`, `cgroup.capabilities`, `cgroup.policy.apply`, `cgroup.policy.clear`, and `cgroup.assignment.get`. They use the same AES-256-GCM sequence-protected channel; no shell command line is accepted.

Process reads come from `/proc`, are bounded by a 1.5 s read budget, a maximum scan of 4096 PIDs, a maximum page of 100 rows, and 4096 bytes of cmdline. Process disappearance or permission races are per-process omissions, not global list failures. Environment variables, open descriptors, memory contents and credentials are not exposed.

Signals are restricted to `SIGINT`, `SIGTERM`, and `SIGKILL`, rate-limited, same-EUID only, require the observed start-time identity to prevent PID reuse, and block PID 1, the cloudos-core process and essential init/system processes. The HTTP layer additionally requires an authenticated admin session and explicit confirmation.

## cgroups v2

Default mode is read-only. `CLOUDOS_WSL_CORE_CGROUP_CONTROL=1` only requests control; it does not guarantee that control is available. The daemon reports cgroup v2 mount state, current cgroup, controllers, delegated controllers, writable files, systemd presence, metrics and an explicit reason when control is unavailable.

When the feature flag is off, writes are rejected. When it is on, control is still rejected unless safe delegation is proven. The implementation never writes the root cgroup, `cgroup.subtree_control`, WSL configuration or another user's cgroup; it never invokes sudo/UAC and never enables systemd. A control assignment can only create a `cloudos-*` child beneath the core's current non-root cgroup, apply validated `memory.max`, `memory.high`, `cpu.max` and/or `pids.max`, and move a same-user process whose PID identity still matches. Assignments are tracked and rolled back on clear/shutdown.

Conservative policy ranges are centralized: memory 64 MiB–16 GiB, CPU 10–400%, and PIDs 16–4096.

## Backend feature flags

Required for Linux System Center:

```text
CLOUDOS_WSL_CORE_FOUNDATION=1
CLOUDOS_WSL_CORE_SYSTEM_CENTER=1
CLOUDOS_WSL_CORE_LINUX_PATH=/absolute/linux/path/cloudos-core
```

Explicit virtual fallback permission, never automatic:

```text
CLOUDOS_WSL_CORE_SYSTEM_CENTER_FALLBACK=1
```

Experimental cgroup control request, disabled by default:

```text
CLOUDOS_WSL_CORE_CGROUP_CONTROL=1
```

## Physical validation

`scripts/validate-linux-system-center-cgroups.ps1` uses a temporary CloudOS runtime/database and a temporary guest binary. It first validates the visible System Center in read-only cgroup mode, with real benign Linux processes, search/state filtering/manual refresh, SIGINT and SIGTERM. It then stops that runtime and performs a direct protected-channel cgroup capability probe. If safe control is reported available, the probe creates only an allowlisted `/bin/sleep` child of that exact core, applies a conservative policy, reads the assignment back, reverts it, and cleans the process. Lack of delegation is a valid read-only result, not a validation failure.

The final report keeps three separate facts: `cgroupReadOnlyValidated`, `cgroupControlAvailable`, and `cgroupControlValidated`. It also fingerprints the real database paths and WSL distro/version/default state and checks temporary core/process PIDs for orphans.
