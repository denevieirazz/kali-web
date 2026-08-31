# CloudOS.NativeCommon

Small shared native protocol definitions live here. This directory is intentionally narrow: it is for ABI/protocol data that must be consumed by more than one native executable, not for general shell helpers.

## Current authority

`native_supervisor_protocol_v11.h` defines the Supervisor V11 contract shared by `CloudOS.exe` and `CloudOS.Supervisor.exe`, including supervised/probe arguments, health/readiness identifiers, desktop/tray classes and the graceful-exit message.

The header also protects the fixed V9 health snapshot layout used by the external supervisor. Treat that layout as an ABI: changing field order, size or interpretation requires an explicit versioned protocol rather than an in-place edit.

## Rule

If a type is used only inside NativeShell, keep it in NativeShell. If it is used only by the supervisor, keep it in NativeRecovery. Add material here only when cross-process/native-project compatibility requires a shared source of truth.
