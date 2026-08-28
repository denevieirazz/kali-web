# CloudOS PR #16 — Physical Windows Runtime Matrix State

PRODUCT_TESTED_SHA=d53298b1c023279206418bf11ec06d98a5a6783f
PR=16
PR_BRANCH=fix/cloudos-runtime-launch-rebind
EVIDENCE_BRANCH=evidence/pr16-physical-d53298b
CURRENT_PHASE=READY_FOR_PHYSICAL_RETEST
LAST_COMPLETED_CASE=AUTOMATED_CI
NEXT_CASE=PREEXISTING_EXTERNAL_SINGLETON
TOTAL_RUNS=0
PASS=0
FAIL=0
EXPECTED_FAIL_CLOSED=0
EXTERNAL_WINDOW_LEAK=UNKNOWN
ALT_TAB_LEAK=UNKNOWN
ORPHAN_PROCESS=UNKNOWN
CROSS_JOB_ADOPTION=UNKNOWN
PHYSICAL_RUNTIME_GATE=PENDING

## Automated gates for exact product SHA

- CloudOS CI Baseline: run 33187588685 — SUCCESS
- Windows Installer Capability CI: run 33187589054 — SUCCESS
- Backend/integration Windows live external-instance probe: PASS
- CloudOS.Host build/tests: PASS
- Browser lifecycle/WebView2: PASS

## Regression being retested

Previous physical SHA `ad9639f1ce8d808d2d532404fd9ca6673244052e` demonstrated a Win32 singleton/handoff escape with Telegram: the observed GUI process was outside the CloudOS Job (`InJob=false`, `OwnedByHost=false`) and appeared as an external desktop/Alt+Tab window.

The current SHA adds a generic preflight guard for direct Win32 executable/shortcut launches. If an instance of the exact same executable already exists and the runtime class has no explicit per-launch isolation namespace, launch must fail closed before the Host receives a launch descriptor. Chromium/Firefox launches with CloudOS-owned unique per-launch profiles remain exempt from this conservative singleton guard.

## Required physical cases

1. `preexisting-external-singleton`
   - Start a direct Win32 app externally first.
   - Launch the same catalog app from CloudOS.
   - Expected: CloudOS blocks before contained `CreateProcess`; no new external window, no activation/handoff, no cross-Job adoption.

2. `fresh-win32-direct`
   - Ensure no instance of the target executable exists.
   - Launch it from CloudOS.
   - Expected: root/final GUI remains attributable to the CloudOS Job; source stays behind CloudOS; no taskbar/Alt+Tab leak.

3. `close-reopen`
   - Close the contained app, verify Job members are gone, then reopen.
   - Expected: clean new launch capability and no orphan process.

4. `second-contained-nonisolated-instance`
   - Keep first non-isolated direct Win32 launch alive and request a second launch of the exact executable.
   - Expected current policy: fail closed rather than risk same-executable singleton handoff.

5. `chromium-isolated-concurrency`
   - Launch two CloudOS browser instances using the generated per-launch profile namespaces.
   - Expected: both launches remain independently attributable; no external singleton delegation.

6. `splash-or-child-gui`
   - Use a compatible app that transitions splash/bootstrap -> final HWND or launcher -> child GUI within the Job.
   - Expected: frontend rebinds by `launchProcessId`; no same-PID assumption.

7. `brokered-boundary`
   - Exercise a known `windows-start-app`/brokered entry.
   - Expected: explicit fail-closed containment message and no external launch.

8. `multiwindow-limit-characterization`
   - Exercise a genuine multiwindow/modal app.
   - Expected: no arbitrary cross-window adoption. Ambiguous replacement remains fail closed until multi-surface support exists.

## Merge gate

PR #16 remains DRAFT. Do not merge unless `PHYSICAL_RUNTIME_GATE=PASS` for this exact `PRODUCT_TESTED_SHA` and there is no external-window/Alt+Tab leak in supported compatible Win32 classes.
