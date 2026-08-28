# PR #16 Physical Matrix Entry Point

This directory is the checkpoint surface for the physical Windows validation of CloudOS PR #16.

- **Product under test:** `ad9639f1ce8d808d2d532404fd9ca6673244052e`
- **Product branch:** `fix/cloudos-runtime-launch-rebind`
- **Evidence branch:** `evidence/pr16-physical-ad9639f`
- **Current gate:** `PENDING`

## Local agent entry sequence

1. Read `GEMINI_HANDOFF.md`.
2. Run `PREPARE_LOCAL_MATRIX.ps1` from an existing Windows clone/worktree context.
3. Keep the PRODUCT worktree detached/pinned exactly to the product SHA above.
4. Keep this EVIDENCE worktree on `evidence/pr16-physical-ad9639f`.
5. Launch CloudOS from the PRODUCT worktree using the official `Iniciar CloudOS.cmd Full` launcher.
6. Execute the runtime-class matrix, writing all evidence into this directory.
7. Update `CURRENT_STATE.md`, `PHYSICAL_MATRIX_REPORT.md`, and `PHYSICAL_MATRIX_REPORT.json` after each meaningful scenario.
8. Run `VALIDATE_REPORT.ps1` to validate report consistency.
9. Use `CHECKPOINT_EVIDENCE.ps1` after each scenario. `PUSH-EVIDENCE.cmd` is the emergency double-click equivalent.

Do not store passwords, recovery codes, authorization tokens, cookies, or other secrets in evidence. Do not modify product source while collecting a scenario. If a real product defect is found, preserve and push the smallest reproducible evidence before changing the product branch.

A gate `PASS` covers compatible Win32 applications inside the current CloudOS Job/capture boundary; it is not a claim that every possible Windows program is containable.
