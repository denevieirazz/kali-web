# CloudOS Transactional Deployment V13

V13 makes native CloudOS installation and updates recoverable before any opt-in Windows logon-shell work is attempted.

## Scope

V13 is deliberately a **per-user filesystem deployment layer**. It does not modify Winlogon, `HKLM`, `HKCU` shell registry values, Explorer startup policy, logoff behavior, or boot configuration.

Default managed root:

`%LOCALAPPDATA%\CloudOS\NativeShell`

Layout:

```text
NativeShell\
  versions\
    g<git>-f<fingerprint>\   immutable verified release
  staging\                   transaction-local copy before publish
  state\
    deployment-v13.json      authoritative active/LKG pointer
    deployment-v13.journal.json  transient transaction journal
    deployment-v13.lock      single-writer lock
  tools\                     stable V13 recovery/status tools
  Iniciar CloudOS.cmd
  Recuperacao CloudOS.cmd
  Rollback CloudOS.cmd
```

The active release is never updated in place. A candidate package is copied to a same-root staging directory, SHA256/manifest validated, and `CloudOS.Supervisor.exe --self-test` must succeed before the version directory can be published and selected as active.

## Transaction model

1. Acquire an exclusive deployment lock.
2. Repair/clean a known interrupted V13 journal if present.
3. Validate the source package authority, x64/Release manifest and all three required binary hashes.
4. Copy to a unique staging directory.
5. Validate the staged copy again and execute Supervisor V11 self-test.
6. Move the verified staging directory to its immutable version directory.
7. Write the active version state atomically. The prior active version becomes `last_known_good`.
8. Prune only versions that are neither active nor last-known-good after the state commit.
9. Clear the journal.

A corrupt package is rejected before active-state mutation. Repeating installation of the same verified package is idempotent.

## Rollback and repair

`rollback-cloudos-native-v13.ps1` validates `last_known_good` before swapping it with the current active version. This makes the rollback itself reversible.

`repair-cloudos-native-v13.ps1` is independent of the CloudOS UI. It cleans staging left by an interrupted pre-activation transaction. If the active version is invalid and a valid last-known-good version exists, repair promotes that verified fallback.

`uninstall-cloudos-native-v13.ps1` refuses to recursively remove a directory unless it contains a valid CloudOS V13 managed state. It also refuses removal while a CloudOS process is running from the managed root.

## Portable package entrypoints

The x64 portable package exposes:

- `Instalar CloudOS.cmd`
- `Atualizar CloudOS.cmd`
- `Rollback CloudOS.cmd`
- `Reparar CloudOS.cmd`
- `Desinstalar CloudOS.cmd`
- the corresponding PowerShell entrypoints and `CloudOS.Deployment.V13.psm1`

The original portable `Iniciar CloudOS.cmd` remains available and still delegates runtime recovery authority to `CloudOS.Supervisor.exe` V11.

## CI acceptance

`test-transactional-deployment-v13-contract.ps1` protects the safety invariants and rejects registry/Winlogon activation code in the V13 deployment module.

`run-native-deployment-smoke-v13.ps1` runs entirely under a temporary directory on the hosted Windows runner and verifies:

1. clean verified install;
2. repeated install is idempotent;
3. verified upgrade preserves previous active as last-known-good;
4. deliberately corrupted binary package is rejected without changing active/LKG state;
5. interrupted pre-activation staging/journal is repaired;
6. rollback restores the exact previous verified version;
7. uninstall removes only the managed temporary root.

The smoke invokes the real compiled `CloudOS.Supervisor.exe --self-test` when a version is published.

## Explicit non-coverage

Hosted CI does **not** validate:

- real Winlogon shell replacement;
- logoff/login;
- reboot/startup recovery;
- machine-wide install/elevation;
- Explorer replacement;
- code-signing trust prompts;
- physical suspend/RDP/hotplug behavior.

Those remain separate acceptance gates. V13 must be green before an opt-in shell-activation stage can safely build on it.
