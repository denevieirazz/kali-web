# CloudOS PR #16 — Physical Windows Runtime Matrix

PRODUCT_TESTED_SHA=`ad9639f1ce8d808d2d532404fd9ca6673244052e`

PR_BRANCH=`fix/cloudos-runtime-launch-rebind`

EVIDENCE_BRANCH=`evidence/pr16-physical-ad9639f`

PHYSICAL_RUNTIME_GATE=`PENDING`

Automated CI for this exact product SHA is green. This document is intentionally incomplete until the Windows-host physical matrix is executed.

| CASE | APP/EXECUTABLE | RUNTIME CLASS | RUNS | PASS | FAIL | FAIL-CLOSED EXPECTED | EXTERNAL WINDOW LEAK | ALT-TAB LEAK | ORPHAN PROCESS | JOB/launchProcessId RESULT | CAPTURE RESULT | CLOSE/REOPEN RESULT | EVIDENCE PATH | VERDICT |
|---|---|---|---:|---:|---:|---:|---|---|---|---|---|---|---|---|
| win32-simple | PENDING | Win32 simple | 0 | 0 | 0 | 0 | UNKNOWN | UNKNOWN | UNKNOWN | PENDING | PENDING | PENDING | PENDING | PENDING |
| splash-bootstrap | PENDING | splash/bootstrap -> final HWND | 0 | 0 | 0 | 0 | UNKNOWN | UNKNOWN | UNKNOWN | PENDING | PENDING | PENDING | PENDING | PENDING |
| child-gui | PENDING | launcher/wrapper -> descendant GUI | 0 | 0 | 0 | 0 | UNKNOWN | UNKNOWN | UNKNOWN | PENDING | PENDING | PENDING | PENDING | PENDING |
| electron-chromium | PENDING | Electron/Chromium-like | 0 | 0 | 0 | 0 | UNKNOWN | UNKNOWN | UNKNOWN | PENDING | PENDING | PENDING | PENDING | PENDING |
| shortcut-args | PENDING | shortcut with safe argv | 0 | 0 | 0 | 0 | UNKNOWN | UNKNOWN | UNKNOWN | PENDING | PENDING | PENDING | PENDING | PENDING |
| dual-instance | PENDING | simultaneous launches | 0 | 0 | 0 | 0 | UNKNOWN | UNKNOWN | UNKNOWN | PENDING | PENDING | PENDING | PENDING | PENDING |
| close-reopen | PENDING | lifecycle | 0 | 0 | 0 | 0 | UNKNOWN | UNKNOWN | UNKNOWN | PENDING | PENDING | PENDING | PENDING | PENDING |
| multiwindow-limit | PENDING | multiwindow/modal ambiguity | 0 | 0 | 0 | 0 | UNKNOWN | UNKNOWN | UNKNOWN | PENDING | PENDING | PENDING | PENDING | PENDING |
| stress | PENDING | repeated lifecycle | 0 | 0 | 0 | 0 | UNKNOWN | UNKNOWN | UNKNOWN | PENDING | PENDING | PENDING | PENDING | PENDING |

## Gate rules

`PHYSICAL_RUNTIME_GATE=PASS` is allowed only when every applicable representative passes containment/lifecycle assertions, no external desktop/Alt+Tab leak is observed, no cross-Job adoption occurs, no orphan process remains after close, dual-instance isolation holds, and unsupported or ambiguous topologies fail closed.

Allowed per-case verdicts: `PASS`, `PASS_EXPECTED_FAIL_CLOSED`, `FAIL`, `BLOCKED_NO_LOCAL_REPRESENTATIVE`, `NOT_APPLICABLE`.
