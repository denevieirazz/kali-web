# Windows Captured-Surface — Physical Finalization Runbook

> Status: POC / PR draft. Do not merge on the basis of CI-only evidence.

This runbook is intentionally executor-only. The physical Windows machine must not edit, fix, commit, push, or invent a fallback. All failures are evidence for the engineering branch.

## Executor role

```text
VOCÊ É APENAS O EXECUTOR/TESTADOR LOCAL DO CLOUDOS.
NÃO EDITE CÓDIGO.
NÃO TENTE CORRIGIR.
NÃO COMMIT.
NÃO PUSH.
NÃO USE --disable-gpu COMO CORREÇÃO.
NÃO ABRA O APP FORA DO CLOUDOS COMO FALLBACK.
SE UM GATE FALHAR, PRESERVE O ERRO/JSON/LOG E REPORTE.
```

## 1. Sync exact branch

Run from the existing proof checkout. Do not use `git clean -fd`.

```powershell
Set-Location 'C:\CloudOS-Proof'
git fetch origin
git switch -C `
  poc/cloudos-windows-captured-surface `
  origin/poc/cloudos-windows-captured-surface

Write-Host '=== BRANCH ==='
git branch --show-current
Write-Host '=== HEAD ==='
$head = (git rev-parse HEAD).Trim()
$head
Write-Host '=== STATUS BEFORE ==='
git status --short
```

Expected branch:

```text
poc/cloudos-windows-captured-surface
```

The SHA must be copied exactly into the evidence report. Do not use a SHA from this document; use the value printed by the checkout.

## 2. Resolve local .NET

```powershell
$dotnetDir = 'C:\Users\dougl\AppData\Local\Microsoft\dotnet'
if (Test-Path -LiteralPath $dotnetDir) {
  $env:DOTNET_ROOT = $dotnetDir
  $env:PATH = "$dotnetDir;$env:PATH"
}
dotnet --info
```

## 3. One-command foundation finalization

```powershell
Set-Location 'C:\CloudOS-Proof'
$head = (git rev-parse HEAD).Trim()

pwsh -NoProfile -File `
  scripts/finalize-windows-captured-surface.ps1 `
  -ExpectedHeadSha $head `
  -CaptureSeconds 5 `
  -MinimumFrames 10

$finalizeExit = $LASTEXITCODE
Write-Host "FINALIZE_EXIT=$finalizeExit"
```

The finalizer deliberately runs both boundaries independently:

1. HWND/WGC five-lane matrix + monitor lower-layer control + native C++/WinRT reference.
2. WGC -> native frame sink -> D3D11/DXGI swapchain -> Host-owned tool HWND presenter.

A failure in the first gate does not suppress the second diagnostic boundary.

## 4. Collect evidence

```powershell
$evidence = 'C:\CloudOS-Proof\poc1-physical-evidence\windows-captured-surface'

Write-Host '=== FINAL SUMMARY ==='
Get-Content "$evidence\physical-finalization-summary.json" -Raw -ErrorAction SilentlyContinue

Write-Host '=== FINAL LOG ==='
Get-Content "$evidence\physical-finalization.log" -Raw -ErrorAction SilentlyContinue

Write-Host '=== HWND MATRIX ==='
Get-Content "$evidence\fixture-wgc-matrix-summary.json" -Raw -ErrorAction SilentlyContinue

Write-Host '=== PRESENTER ==='
Get-Content "$evidence\fixture-presenter-smoke.json" -Raw -ErrorAction SilentlyContinue

Write-Host '=== PRESENTER LOG ==='
Get-Content "$evidence\fixture-presenter-smoke.log" -Raw -ErrorAction SilentlyContinue

Write-Host '=== STATUS AFTER ==='
git status --short
```

Return the complete output plus the exact HEAD SHA. Existing unrelated untracked physical-evidence files are not a reason to clean the repository.

## Decision tree

### A. HWND matrix fails, monitor control passes

Keep the blocker classified at the HWND / `GraphicsCaptureItem` / capture-session boundary. Compare the C# product-candidate lane with the independent C++/WinRT reference on the same HWND. Do not blame the D3D lower layer and do not modify the presenter first.

### B. HWND matrix passes, presenter fails

The capture foundation is healthy. Restrict diagnosis to native presentation: captured `ID3D11Texture2D`, source device identity, DXGI factory/swapchain creation, backbuffer dimensions, `CopyResource`, `Present`, Host-owned surface layout/device loss.

### C. Both foundation gates pass

Advance in this order:

1. ordinary real Win32 app;
2. Brave/Chromium with GPU enabled;
3. frame-health: changing hashes, non-flat sequence, no gray/static renderer;
4. source HWND isolation: no normal desktop appearance and no independent Alt+Tab entry;
5. input pointer/client mapping, keyboard/focus, DPI, resize, minimize/restore;
6. two simultaneous captured apps;
7. close -> exact process/Job termination/revocation -> reopen with a new generation;
8. install a previously unknown ordinary app -> force catalog rescan -> verify new opaque app entry -> qualify/run with no app-specific code.

## Product rules that remain fail-closed

- No generic cross-process `SetParent`.
- No per-frame PNG/JPEG through the WebView bridge.
- No `--disable-gpu` shipping workaround.
- No automatic fallback to a loose Windows desktop window.
- No `CAPTURE_SUPPORTED` classification from filename, framework, registry key, or heuristic alone.
- Broker/singleton/shared-process escape must be rejected or explicitly qualified; never guessed safe.
- A stale surface generation or replayed input sequence must be rejected.
- PR remains draft until physical/UX gates are proven.
