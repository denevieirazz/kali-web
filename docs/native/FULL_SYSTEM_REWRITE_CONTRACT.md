# CloudOS Native Full-System Rewrite Contract

## Objective

Rewrite the complete CloudOS product as a native Windows system while preserving the behavior and product scope of the current integrated CloudOS tree.

This is **not** a small replacement shell. The existing full tree is the migration oracle until native parity is proven.

## Non-negotiable rule

Do not delete, hide, or replace a working CloudOS subsystem merely because a native bootstrap exists.

A legacy subsystem can be retired only after its native replacement has:

1. the same user-visible capability or an explicitly approved improvement;
2. native unit/contract tests where applicable;
3. integration coverage;
4. Windows x64 CI green;
5. lifecycle/error handling verified;
6. migration evidence recorded.

## Product scope that must survive the rewrite

### Shell / desktop
- boot, account and session lifecycle;
- desktop, taskbar, start menu, launcher/spotlight;
- real Windows program management;
- window focus, snap, tiling, workspaces, DPI and multi-monitor;
- settings, notifications and shell persistence.

### Terminal / WSL / runtime
- ConPTY terminal sessions;
- PowerShell/CMD profiles;
- WSL/Kali profiles;
- Windows and WSL process execution;
- process containment / Job Objects;
- native process inventory and lifecycle;
- WSL distribution/configuration integration.

### Files / workspace
- CloudOS Drive / virtual workspace semantics;
- Windows filesystem access;
- WSL filesystem access and path translation;
- project scopes;
- import/export;
- notes, evidence and reports;
- persistence and recovery.

### Development / productivity apps
- code editor;
- Python runner;
- terminal workflows;
- projects;
- file manager;
- system/process monitor;
- report builder/generator.

### Security tooling already present in CloudOS
Native rewrite must preserve the product integrations and safety/scope controls around the current scanners and security apps, including the existing Nmap, SQLMap, OSINT, Metasploit/MSFVenom, hash, privilege-escalation helper, pipeline/automation, attack graph, evidence and reporting workflows.

The rewrite must preserve authorization/scope enforcement and structured execution. Do not replace validated argument handling with interpolated shell strings.

## Migration strategy

### Phase A - native substrate
Keep the entire current CloudOS tree and add native infrastructure beside it:
- `CloudOS.NativeRuntime`;
- `CloudOS.NativeShell`;
- ConPTY;
- WinEvent HWND registry;
- Job Objects;
- WSL API capability layer;
- native window/workspace manager.

### Phase B - native system services
Port stateful services before deleting any web/service implementation:
- settings/profile/session state;
- filesystem and path translation;
- project/workspace persistence;
- process manager;
- WSL manager;
- app catalog/launcher;
- evidence/report persistence;
- security scope policy.

### Phase C - native applications
Port applications feature-for-feature. Native apps may share common C++ service libraries instead of reproducing HTTP boundaries that existed only for the browser architecture.

### Phase D - native boot cutover
Only after parity gates pass should `Iniciar CloudOS.cmd` point exclusively at the native product.

### Phase E - legacy removal
Delete React/Vite/Node/C#/WebView sources only after an explicit parity audit shows they are no longer the sole implementation of any CloudOS capability.

## Current status

The C++ native substrate exists and builds. It is a migration foundation, not evidence that the whole CloudOS has already been rewritten.

The authoritative rewrite branch is:

`rewrite/cloudos-native-full-system`

It starts from the latest full integrated CloudOS tree and keeps the legacy implementation available as the parity reference while native equivalents are built.
