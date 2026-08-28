# CloudOS PR #16 — Physical Runtime Matrix State

PRODUCT_TESTED_SHA=ad9639f1ce8d808d2d532404fd9ca6673244052e
PR=16
PR_BRANCH=fix/cloudos-runtime-launch-rebind
EVIDENCE_BRANCH=evidence/pr16-physical-ad9639f
CURRENT_PHASE=READY_FOR_LOCAL_PHYSICAL_MATRIX
LAST_COMPLETED_CASE=AUTOMATED_CI_AND_HARNESS_HARDENING
NEXT_CASE=WIN32_SIMPLE
TOTAL_RUNS=0
PASS=0
FAIL=0
EXPECTED_FAIL_CLOSED=0
EXTERNAL_WINDOW_LEAK=UNKNOWN
ORPHAN_PROCESS=UNKNOWN
CROSS_JOB_ADOPTION=UNKNOWN
PHYSICAL_RUNTIME_GATE=PENDING
LAST_EVIDENCE_COMMIT=a857f0732567c53a27c3779e2928f799ab52fb9f
LAST_PUSH_STATUS=SUCCESS
LAST_PUSH_TIME=2026-08-28T12:50:00Z

## Automated gate completed on the exact product SHA

- CloudOS CI Baseline run `33168545780`: SUCCESS.
- Windows Installer Capability CI run `33168545789`: SUCCESS.
- Main Windows CI job `98839729299`: SUCCESS.
- Installer capability job `98839729401`: SUCCESS.
- Backend/integration test run: 262 passed, 0 failed.
- Frontend unit test run: 228 passed, 0 failed.
- Host build/tests, Playwright characterization, Browser lifecycle and native Browser WebView2 gates: PASS.
- Conditional visual-only workflow steps that were not selected remained `skipped`; they are not failures.

The current CI also executed the new physical-proof source-contract regressions and passed them:

- physical proof scripts do not shadow PowerShell's automatic/read-only `$Host` variable;
- `EnumWindows` diagnostics retain the native Win32 error;
- `ExpectedState=Absent` does not require desktop enumeration after all captured target PIDs have exited.

## Local execution tooling prepared

The evidence branch now contains a fail-closed local workflow so a local Gemini/agent can continue without depending on chat context:

- `GEMINI_HANDOFF.md` — exact scope and two-worktree execution contract.
- `PREPARE_LOCAL_MATRIX.ps1` — safely prepares/verifies a PRODUCT worktree pinned to the exact product SHA and a separate EVIDENCE worktree.
- `CHECKPOINT_EVIDENCE.ps1` — stages only this matrix, validates the product SHA marker, refuses pre-staged unrelated files, scans staged evidence for common credential material, commits and pushes to the evidence branch.
- `PUSH-EVIDENCE.cmd` — emergency double-click publisher that invokes the same fail-closed checkpoint logic.

The PRODUCT worktree must remain exactly at `ad9639f1ce8d808d2d532404fd9ca6673244052e`. The EVIDENCE branch is allowed to advance with report commits. Do not run the SHA-validating product proof from the advancing evidence branch.

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

A physical PASS requires all applicable representatives to remain attributable to the current CloudOS Job/capture boundary, with no external desktop spill, no separate Windows Alt+Tab entry, no cross-Job adoption, no orphan process after close, successful reopen, isolated simultaneous launches where supported, and deterministic fail-closed behavior for ambiguous/incompatible classes.

Do not claim that all Windows programs are supported. Scope is compatible Win32 applications inside the current Job/capture boundary.

## Exact next local action

From an existing clone that can access the Windows desktop, use the helper from the evidence branch to prepare the two worktrees. Then launch CloudOS from the PRODUCT worktree with the official `Iniciar CloudOS.cmd Full` launcher and execute `win32-simple` first using `scripts/run-windows-contained-runtime-physical-proof.ps1` with `-ExpectedHeadSha ad9639f1ce8d808d2d532404fd9ca6673244052e` and the matrix directory in the EVIDENCE worktree as `-OutputDirectory`.

After every meaningful scenario, update the reports and run `CHECKPOINT_EVIDENCE.ps1` (or `PUSH-EVIDENCE.cmd` in an emergency). If a real product bug is found, push the smallest reproducible evidence before attempting a source fix.
