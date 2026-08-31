# CloudOS.NativeRecovery / Supervisor V11

This project builds the external recovery authority:

```text
CloudOS.Supervisor.exe
```

The directory name is historical. The release target is **Supervisor V11**, not a second competing recovery loop and not the old `CloudOS.Recovery.exe` model.

## Source of truth

- `CloudOS.NativeRecovery.vcxproj` — build target and warning policy.
- `main.cpp` — supervisor process, readiness/heartbeat monitoring, bounded restart policy, graceful shutdown and safe Explorer fallback decision.
- `../CloudOS.NativeCommon/native_supervisor_protocol_v11.h` — protocol shared with `CloudOS.exe`.

When CloudOS is launched by the supervisor it receives `--supervised`; in that mode the embedded watchdog does not create a second recovery loop.

## Safety invariants

- No automatic registry modification belongs here.
- Do not kill Explorer as part of normal supervision.
- Launch Explorer only when fallback is required and no `Shell_TrayWnd` is present.
- Keep recovery process targeting restricted to the same installation path, user SID and session.
- Prefer graceful exit; forced termination is last resort for a hung process.

Runtime behavior is covered by `scripts/native/run-native-supervisor-smoke-v11.ps1` and the V11 contract.
