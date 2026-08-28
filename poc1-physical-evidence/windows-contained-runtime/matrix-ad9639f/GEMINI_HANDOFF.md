# Gemini Local Handoff — CloudOS PR #16 Physical Matrix

This file is an execution handoff for the local Windows agent. It is not product source code.

## Exact source under test

- Repository: `denevieirazz/kali-web`
- PR: `#16`
- Product branch: `fix/cloudos-runtime-launch-rebind`
- Exact product SHA: `ad9639f1ce8d808d2d532404fd9ca6673244052e`
- Evidence branch: `evidence/pr16-physical-ad9639f`
- Evidence directory: `poc1-physical-evidence/windows-contained-runtime/matrix-ad9639f`

Do not test the old `42edbde...` SHA. Do not use `integration/cloudos-unified-runtime` as the product under test.

## Known previous blocker — already fixed

An earlier local proof attempt was blocked by the proof harness itself. The current product SHA includes fixes and regression coverage for both known harness faults:

1. `scripts/run-windows-contained-runtime-physical-proof.ps1` no longer shadows PowerShell's read-only automatic `$Host` variable.
2. `scripts/collect-windows-native-containment-evidence.ps1` does not require `EnumWindows` for `ExpectedState=Absent` after every captured target PID has already exited; `EnumWindows` failures also preserve native error information.

Do not classify those old harness errors as current runtime failures without reproducing them on the exact SHA above.

## Local resume procedure

1. Fetch origin without rewriting local work.
2. Preserve any existing uncommitted evidence.
3. Ensure the code worktree used to launch CloudOS resolves exactly to the product SHA above.
4. Use the official Full launcher from that worktree.
5. Authentication is only a prerequisite. Use the official login/recovery flow; never log or commit passwords, recovery codes, tokens, cookies, or other secrets.
6. Run the physical matrix by runtime class, not by brand name.
7. Use `scripts/run-windows-contained-runtime-physical-proof.ps1 -ExpectedHeadSha ad9639f1ce8d808d2d532404fd9ca6673244052e` for representative open/close/reopen proofs.
8. Use `scripts/collect-windows-native-containment-evidence.ps1` for narrow machine evidence when a scenario needs additional PID/HWND/Job characterization.
9. After every meaningful scenario, update `CURRENT_STATE.md`, `PHYSICAL_MATRIX_REPORT.md`, and `PHYSICAL_MATRIX_REPORT.json`.
10. Commit only evidence and push only to `evidence/pr16-physical-ad9639f`.

## Physical matrix

Required classes when a local representative is available:

- Win32 simple single-window.
- Splash/bootstrap -> final HWND.
- Launcher/wrapper -> descendant GUI PID.
- Electron/Chromium-like.
- Shortcut with safe arguments.
- Two simultaneous launches of the same compatible executable.
- Close -> full process tree exit -> reopen with a new PID.
- Multiwindow/modal ambiguity characterization.
- Stress cycles after representative cases pass.

For each scenario record launch/root PID, known member PIDs, physical HWND-owner PID, public `launchProcessId` when available, session IDs, containment mode, close result, reopen result, external-window observation, Alt+Tab observation, and evidence paths.

## Gate rule

Set `PHYSICAL_RUNTIME_GATE=PASS` only when all applicable representatives pass and there is:

- no external Windows desktop spill;
- no separate target Alt+Tab entry;
- no cross-Job adoption;
- no orphan process after CloudOS closes the session;
- correct close/reopen lifecycle;
- isolated simultaneous launches where supported;
- fail-closed behavior for unsupported or ambiguous candidates.

The supported scope is compatible Win32 applications inside the current Job/capture boundary. Do not claim universal Windows-program compatibility.

If a real product defect is found, preserve and push the smallest reproducible evidence before attempting any source-code fix.
