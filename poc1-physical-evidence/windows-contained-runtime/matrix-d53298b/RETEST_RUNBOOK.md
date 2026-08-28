# PR #16 — Windows physical retest runbook

## Immutable product under test

```text
PRODUCT_TESTED_SHA=d53298b1c023279206418bf11ec06d98a5a6783f
PRODUCT_BRANCH=fix/cloudos-runtime-launch-rebind
EVIDENCE_BRANCH=evidence/pr16-physical-d53298b
```

Do not approve this matrix with evidence produced from `ad9639f1ce8d808d2d532404fd9ca6673244052e`; that SHA is the known failing physical baseline.

## 0. Freeze the product worktree

From the product worktree:

```powershell
Set-Location C:\CloudOS-PR16-Product
git fetch origin
git switch fix/cloudos-runtime-launch-rebind
git reset --hard d53298b1c023279206418bf11ec06d98a5a6783f
git status --porcelain
git rev-parse HEAD
```

Required before testing:

```text
status --porcelain = empty
HEAD = d53298b1c023279206418bf11ec06d98a5a6783f
```

Start the product only through the normal full CloudOS launcher used by the physical matrix. Do not run the target executable manually except when the case explicitly requires a pre-existing external instance.

## 1. Regression A — pre-existing external singleton/handoff

Purpose: reproduce the condition indicated by the previous Telegram evidence, but verify that the new backend guard blocks it before the Host receives a direct launch descriptor.

Procedure:

1. Close CloudOS-managed Telegram if any.
2. Start `Telegram.exe` normally outside CloudOS.
3. Record the external Telegram PID and executable path.
4. Open CloudOS and request Telegram from the app catalog.
5. Observe for at least 5 seconds.

Required PASS:

- launch request is rejected/fails closed;
- no second Telegram root launch is admitted by CloudOS;
- no new external Telegram top-level window is created by the CloudOS action;
- no external window is adopted into a CloudOS `launchProcessId`;
- no cross-Job adoption;
- existing external Telegram stays external and is not terminated or manipulated by CloudOS.

Expected backend semantic result is `EXTERNAL_INSTANCE_CONFLICT` / HTTP 409. Current Host UI may still surface a generic launch failure message; that UX detail is not containment failure.

## 2. Regression B — fresh direct Win32 launch

Purpose: prove that the guard does not merely block Telegram; with no existing instance, the normal generic Job/capture pipeline must work.

Procedure:

1. Exit every `Telegram.exe` instance.
2. Verify no Telegram process remains.
3. Launch Telegram only from CloudOS.
4. Record root launch PID, every Job member PID, final GUI HWND owner PID, `launchProcessId`, containment mode and Alt+Tab/taskbar state.
5. Keep it open for at least 10 seconds and interact with the captured surface.

Required PASS:

- root process is created by the CloudOS Host launch path;
- final GUI PID is a member of the same containment Job or otherwise attributable through the existing launch Job contract;
- `launchProcessId` remains the stable launch root across HWND/PID transition;
- captured source stays behind CloudOS;
- no standalone desktop window;
- no Windows taskbar/Alt+Tab entry for the source;
- pointer and keyboard routing remain functional.

Any `InJob=false` final GUI associated with this fresh launch is FAIL.

## 3. Close/reopen lifecycle

1. Close the contained app through CloudOS.
2. Verify every member PID of that launch Job exits.
3. Verify no source HWND remains visible externally.
4. Launch the same app again from CloudOS.

Required PASS: clean new Job/root identity, no orphan from the first launch, no stale-session adoption.

## 4. Second non-isolated direct launch

While the first fresh non-isolated direct Win32 instance remains alive, request a second launch of the exact same executable.

Expected current policy: fail closed. This conservative rule is deliberate until a generic per-launch namespace exists for that runtime class.

Required PASS: no new external activation/handoff and no cross-Job session adoption.

## 5. Chromium isolated concurrency

Launch two CloudOS Chromium-family instances through the catalog.

Required PASS:

- both receive different 128-bit per-launch profile directories;
- each remains associated with its own launch capability/Job;
- neither delegates to an already-running external browser;
- no external taskbar/Alt+Tab source leak.

## 6. Splash/bootstrap or launcher -> child GUI

Use one compatible representative whose visible final HWND differs from the startup HWND/PID.

Required PASS: replacement session is adopted only when it is the unique `hidden-quarantine` candidate with the same `launchProcessId`.

## 7. Brokered boundary

Use a known `windows-start-app`/UWP/Shell brokered entry.

Required PASS: explicit fail closed; no unmanaged external window appears.

## 8. Evidence fields that must be recorded per case

```text
PRODUCT_TESTED_SHA
case/runtimeClass/target
launch root PID
final HWND
final HWND owner PID
launchProcessId
Job member PIDs
InJob
OwnedByHost / source owner relationship
containmentMode
external desktop window leak
Alt+Tab leak
taskbar leak
cross-Job adoption
orphan process after close
verdict
```

For the pre-existing singleton case also record the PID/path that existed before the CloudOS launch request.

## Final gate

`PHYSICAL_RUNTIME_GATE=PASS` only if the supported compatible Win32 cases have zero external-window/Alt+Tab/taskbar leaks, no cross-Job adoption, no orphaned Job members, and the intentional brokered/non-isolated concurrency boundaries fail closed.

PR #16 remains DRAFT even after this matrix until the separate duplicate-`TryAttach` lock-order review blocker is resolved.
