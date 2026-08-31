# CloudOS native tooling

Use this file to choose the right entrypoint instead of running similarly named scripts by guesswork.

## Developer entrypoints

```text
build-cloudos-native.cmd                 build + structural contracts + manifest verification
start-cloudos-native.cmd                 verified local launch
package-cloudos-native.ps1               portable package
get-native-build-status.ps1              current build/release status
collect-native-diagnostics.ps1           local diagnostics bundle
```

## Contract entrypoint

Run **one** suite:

```powershell
pwsh -NoProfile -File scripts/native/test-native-contract-suite.ps1
```

`test-native-contract-suite.ps1` is the ordered inventory of structural contracts. Individual `test-*-contract.ps1` files remain independently runnable for diagnosis, but the build must not maintain a duplicate list.

Runtime smokes are separate because they require built binaries. The Full-System workflow runs the V9/V10/V11/V12/V13/V14 runtime checks after compilation/package creation.

## Deployment and shell activation

V13 owns per-user versioned deployment:

- `CloudOS.Deployment.V13.psm1`
- install/update/rollback/uninstall entrypoints
- `run-native-deployment-smoke-v13.ps1`

V14 owns explicit per-user shell activation and exact Explorer rollback:

- `CloudOS.ShellActivation.V14.psm1`
- activate/status/repair/rollback entrypoints packaged with the release
- `run-native-shell-activation-smoke-v14.ps1`

Do not replace these with `configure-cloudos-shell-launcher.ps1`. That script is a **LEGACY** Shell Launcher experiment for supported Windows editions and is not the current activation authority.

## Release authority

`write-native-build-manifest.ps1`, `verify-native-build-manifest.ps1` and `get-native-build-fingerprint.ps1` define release integrity/provenance behavior. Packaging must preserve `CloudOS.exe`, `CloudOS.NativeRuntime.dll` and `CloudOS.Supervisor.exe` as the three verified native binaries.

See `docs/native/VALIDATION.md` for what each automated check proves and what still requires a VM or physical machine.
