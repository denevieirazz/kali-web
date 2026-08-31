# CloudOS Shell Activation V14 — opt-in per-user activation with exact rollback

V14 is the first stage that can **optionally** configure CloudOS as the current user's logon shell. It is deliberately separated from V13 deployment and is never activated by install/update/package/CI automatically.

## Why this stage is isolated

Changing the Windows logon shell is a high-impact operation. A bad path, deleted binary or partial update can leave a user with a blank desktop after sign-in. V14 therefore treats shell activation as its own transaction with a pre-change snapshot, recovery journal and an independent Explorer rollback path.

The authoritative CloudOS runtime remains:

1. V13 selects a verified immutable active version under `%LOCALAPPDATA%\CloudOS\NativeShell\versions\...`.
2. V14's stable shell entry reads that V13 state on every launch.
3. The stable entry verifies the active payload and starts that version's `CloudOS.Supervisor.exe`.
4. Supervisor V11 starts `CloudOS.exe --supervised`, waits for V9 readiness/heartbeat and falls back to Explorer after bounded failures.
5. If the stable entry itself fails, its CMD wrapper has an additional Explorer fallback.

This means update/rollback does **not** require rewriting the Winlogon value to a version-specific CloudOS path.

## Registry scope

Production V14 only touches the current-user value:

`HKCU\Software\Microsoft\Windows NT\CurrentVersion\Winlogon\Shell`

It does not write HKLM, `Userinit`, Run/RunOnce, policies, services, scheduled tasks, ACLs or machine-wide startup.

Microsoft's documented managed custom-shell feature is **Shell Launcher**, with edition/management requirements and machine-wide enablement semantics. V14 intentionally does not silently enable Shell Launcher or edit the machine-wide Winlogon Shell value. The HKCU path is therefore an explicit compatibility/opt-in route and must be validated on the exact Windows editions used for a pilot before production rollout.

## Activation transaction

`Ativar CloudOS como Shell.cmd` / `activate-cloudos-shell-v14.ps1`:

1. requires an existing valid V13 deployment;
2. re-verifies the active package and runs the Supervisor self-test;
3. copies stable V14 recovery/entry scripts into `<install>\shell-v14`;
4. snapshots whether `Shell` existed, its exact registry type, and its unexpanded data;
5. writes `state\shell-activation-v14.journal.json` before changing the registry;
6. writes the CloudOS shell command and reads it back;
7. writes `state\shell-activation-v14.json` only after read-back succeeds;
8. deletes the journal only after commit.

Repeated activation with the exact managed value is idempotent. If V14 state says it is active but another tool/user changed `Shell`, activation refuses to overwrite that external change.

V14 does not log off or reboot the user. The change takes effect on a later sign-in initiated by the operator.

## Exact rollback

`Restaurar Explorer.cmd` is copied into the installed root so rollback remains available even when `CloudOS.exe` is broken or the original portable ZIP is gone.

Rollback restores the exact pre-activation state:

- if `Shell` did not exist before activation, it is removed;
- `REG_SZ` is restored as `REG_SZ`;
- `REG_EXPAND_SZ` is restored as `REG_EXPAND_SZ` without environment expansion;
- binary/multi-string/integer kinds are also serialized defensively even though they are not expected for a normal Shell value.

If the current registry value no longer matches the CloudOS-managed value, rollback refuses to overwrite the external change unless an operator deliberately uses the force-snapshot switch after inspection.

## Interrupted activation repair

`Reparar Ativacao do Shell.cmd` checks the V14 journal. If a transaction stopped after writing the registry but before committing state, repair restores the exact snapshot stored before the write and removes the journal.

If there is no pending journal and an active managed value has drifted, repair reports drift and performs no write. This prevents CloudOS from fighting Group Policy, an administrator or another recovery tool.

## Uninstall interlock

The packaged V13 uninstall entrypoint refuses to remove a root while:

- a valid V14 activation state says CloudOS is active as shell; or
- the production HKCU Winlogon Shell string still references that install root.

Rollback the shell first, then uninstall.

## Portable commands

After packaging, the ZIP exposes:

- `Instalar CloudOS.cmd`
- `Atualizar CloudOS.cmd`
- `Ativar CloudOS como Shell.cmd`
- `Status do Shell CloudOS.cmd`
- `Restaurar Explorer.cmd`
- `Reparar Ativacao do Shell.cmd`
- `Rollback CloudOS.cmd` (V13 version rollback, distinct from shell rollback)
- `Desinstalar CloudOS.cmd`
- `Recuperacao CloudOS.cmd`

`Rollback CloudOS.cmd` changes the V13 active application version. `Restaurar Explorer.cmd` changes the Windows logon shell back to exactly what existed before V14 activation. They solve different problems.

## Hosted CI coverage

The V14 Windows CI smoke uses only:

`HKCU\Software\CloudOS\Tests\ShellActivationV14\<random-id>`

It asserts:

- clean V13 deployment before activation;
- no prior Shell -> activate -> rollback to absence;
- prior `explorer.exe` -> exact restore;
- prior `REG_EXPAND_SZ` custom string -> exact type/data restore;
- repeated activation is idempotent;
- the installed stable entry resolves the V13 active version and passes a real Supervisor/CloudOS readiness probe;
- deterministic interruption after registry write leaves a journal and repair restores the prior value;
- missing/corrupt active payload prevents activation;
- uninstall is blocked while shell activation is active;
- uninstall succeeds after shell rollback;
- the real current-user Winlogon Shell snapshot is byte/semantic-equivalent before and after the smoke.

Hosted CI does **not** log off, reboot, replace the runner shell, write HKLM, enable Shell Launcher, or claim boot/login validation.

## Physical VM acceptance matrix before real use

A real opt-in pilot still needs an isolated Windows VM/snapshot for each supported edition/build:

1. activate -> log off -> sign in -> CloudOS reaches Ready;
2. close CloudOS normally -> Explorer becomes usable;
3. crash CloudOS before Ready -> bounded Supervisor restart -> Explorer fallback;
4. hang heartbeat -> Supervisor recovery -> Explorer fallback;
5. delete/corrupt active CloudOS payload before sign-in -> stable entry falls back to Explorer;
6. V13 update while V14 is active -> next sign-in launches new active version without changing registry command;
7. V13 rollback while V14 is active -> next sign-in launches LKG version;
8. interrupt activation between registry write and state commit -> offline/next-session repair restores prior Shell;
9. run `Restaurar Explorer.cmd` with CloudOS UI unusable -> next sign-in uses prior shell;
10. attempt uninstall while V14 active -> uninstall is refused;
11. rollback shell -> uninstall -> Explorer sign-in remains normal;
12. verify Task Manager / Ctrl+Alt+Del / recovery access in every failure case.

Do not treat the hosted CI smoke as proof of the real logon matrix. V14 makes activation reversible and testable; it does not remove the need for VM validation before replacing Explorer on a daily-use account.
