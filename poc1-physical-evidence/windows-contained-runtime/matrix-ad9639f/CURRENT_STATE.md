# CloudOS PR #16 — Physical Runtime Matrix State

PRODUCT_TESTED_SHA=ad9639f1ce8d808d2d532404fd9ca6673244052e
PR=16
PR_BRANCH=fix/cloudos-runtime-launch-rebind
EVIDENCE_BRANCH=evidence/pr16-physical-ad9639f
CURRENT_PHASE=READY_FOR_PHYSICAL_WINDOWS_MATRIX
LAST_COMPLETED_CASE=AUTOMATED_CI
NEXT_CASE=WIN32_SIMPLE
TOTAL_RUNS=0
PASS=0
FAIL=0
EXPECTED_FAIL_CLOSED=0
EXTERNAL_WINDOW_LEAK=UNKNOWN
ORPHAN_PROCESS=UNKNOWN
CROSS_JOB_ADOPTION=UNKNOWN
PHYSICAL_RUNTIME_GATE=PENDING
LAST_EVIDENCE_COMMIT=INITIALIZED_REMOTE
LAST_PUSH_STATUS=SUCCESS
LAST_PUSH_TIME=2026-08-28T12:00:00Z

## Automated gate already completed

- CloudOS CI Baseline run 33168545780: SUCCESS.
- Windows Installer Capability CI run 33168545789: SUCCESS.
- The physical-proof harness regressions discovered during the earlier Gemini attempt were corrected before this matrix:
  - PowerShell automatic `$Host` variable is no longer shadowed by the proof scripts.
  - Absent-state collection no longer depends on a desktop `EnumWindows` pass once every captured target PID has exited.
  - `EnumWindows` failures now retain the native Win32 error code.
  - `backend/test/windows-physical-proof-contract.test.js` locks these contracts.

## Required physical cases

1. Win32 simple single-window.
2. Splash/bootstrap -> final HWND.
3. Launcher/wrapper -> descendant GUI PID.
4. Electron/Chromium-like.
5. Shortcut with safe arguments.
6. Two simultaneous contained launches of the same compatible executable.
7. Close -> process tree exit -> reopen with new PID.
8. Multiwindow/modal characterization; ambiguous replacement must fail closed.
9. Stress cycles after the representative cases pass.

## Required assertions

A physical PASS requires all applicable representatives to remain attributable to the current CloudOS Job/capture boundary, with no external desktop spill, no separate Windows Alt+Tab entry, no cross-Job adoption, no orphan process after close, successful reopen, and deterministic fail-closed behavior for ambiguous/incompatible classes.

Do not claim that all Windows programs are supported. Scope is compatible Win32 applications inside the current Job/capture boundary.

## Resume rule for local agents

Use the exact product SHA above. Do not edit source code during evidence collection. Update this file after each scenario, commit only evidence under this matrix directory, and push only to the evidence branch. If a real product bug is found, preserve the evidence and stop that scenario before attempting a code fix on the PR branch.
