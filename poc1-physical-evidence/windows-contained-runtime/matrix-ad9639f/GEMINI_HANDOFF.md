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

## Critical topology: use two worktrees

Do not run the physical proof from the evidence branch after evidence commits have advanced it past the product SHA. The proof script intentionally validates the current Git HEAD, so product execution and evidence persistence must be separated.

Use two worktrees:

1. **PRODUCT worktree** — detached or otherwise pinned exactly at `ad9639f1ce8d808d2d532404fd9ca6673244052e`. Launch CloudOS and run all product/proof scripts from here. Never commit evidence from this worktree.
2. **EVIDENCE worktree** — checked out on `evidence/pr16-physical-ad9639f`. Store reports/screenshots/logs here and commit/push checkpoints from this worktree only.

A safe local shape is:

```powershell
$repo = 'C:\kali-web-sandbox-test'
$product = 'C:\CloudOS-PR16-Product'
$evidence = 'C:\CloudOS-PR16-Evidence'
$sha = 'ad9639f1ce8d808d2d532404fd9ca6673244052e'

git -C $repo fetch origin --prune
git -C $repo cat-file -e "$sha^{commit}"

# Inspect existing worktrees first; never delete an unknown worktree with uncommitted data.
git -C $repo worktree list --porcelain

# Create only when the destination does not already exist.
# Product worktree stays pinned to the exact tested SHA.
git -C $repo worktree add --detach $product $sha

# Evidence worktree follows the checkpoint branch.
git -C $repo worktree add $evidence evidence/pr16-physical-ad9639f
```

If either directory already exists, inspect `git status`, `git rev-parse HEAD`, and `git branch --show-current` there instead of deleting/recreating it.

Before every physical scenario verify in the PRODUCT worktree:

```powershell
git rev-parse HEAD
```

It must equal exactly:

`ad9639f1ce8d808d2d532404fd9ca6673244052e`

Point the proof output into the EVIDENCE worktree, for example:

```powershell
$matrix = 'C:\CloudOS-PR16-Evidence\poc1-physical-evidence\windows-contained-runtime\matrix-ad9639f'
Set-Location 'C:\CloudOS-PR16-Product'
.\scripts\run-windows-contained-runtime-physical-proof.ps1 `
  -ExpectedHeadSha ad9639f1ce8d808d2d532404fd9ca6673244052e `
  -ProofName win32-simple `
  -OutputDirectory $matrix
```

This lets the evidence branch advance after every checkpoint without invalidating the tested source SHA.

## Known previous blocker — already fixed

An earlier local proof attempt was blocked by the proof harness itself. The current product SHA includes fixes and regression coverage for both known harness faults:

1. `scripts/run-windows-contained-runtime-physical-proof.ps1` no longer shadows PowerShell's read-only automatic `$Host` variable.
2. `scripts/collect-windows-native-containment-evidence.ps1` does not require `EnumWindows` for `ExpectedState=Absent` after every captured target PID has already exited; `EnumWindows` failures also preserve native error information.

Do not classify those old harness errors as current runtime failures without reproducing them on the exact SHA above.

## Local resume procedure

1. Fetch origin without rewriting local work.
2. Inspect existing worktrees and preserve any uncommitted evidence.
3. Keep the PRODUCT worktree pinned exactly to the product SHA above.
4. Keep the EVIDENCE worktree on `evidence/pr16-physical-ad9639f` and pull it fast-forward-only before writing new checkpoints.
5. Use the official Full launcher from the PRODUCT worktree.
6. Authentication is only a prerequisite. Use the official login/recovery flow; never log or commit passwords, recovery codes, tokens, cookies, or other secrets.
7. Run the physical matrix by runtime class, not by brand name.
8. Use `scripts/run-windows-contained-runtime-physical-proof.ps1 -ExpectedHeadSha ad9639f1ce8d808d2d532404fd9ca6673244052e -OutputDirectory <matrix-in-evidence-worktree>` for representative open/close/reopen proofs.
9. Use `scripts/collect-windows-native-containment-evidence.ps1` from the PRODUCT worktree for narrow machine evidence when a scenario needs additional PID/HWND/Job characterization; always write its output into the EVIDENCE worktree.
10. After every meaningful scenario, update `CURRENT_STATE.md`, `PHYSICAL_MATRIX_REPORT.md`, and `PHYSICAL_MATRIX_REPORT.json` in the EVIDENCE worktree.
11. Before every evidence commit run `git status --porcelain` in the EVIDENCE worktree and confirm no secret/private machine data is staged.
12. Commit and push only from the EVIDENCE worktree to `evidence/pr16-physical-ad9639f`.

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

## Checkpoint rule

Do not wait for the whole matrix before pushing. After each representative case or meaningful stress block:

```powershell
Set-Location 'C:\CloudOS-PR16-Evidence'
git status --porcelain
git add -- 'poc1-physical-evidence/windows-contained-runtime/matrix-ad9639f'
git diff --cached --name-only
git commit -m "test(evidence): checkpoint <scenario>"
git push origin evidence/pr16-physical-ad9639f
```

If there is nothing to commit, continue. If anything outside the matrix directory is staged, unstage it and investigate before committing.

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
