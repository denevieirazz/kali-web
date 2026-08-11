$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not (Test-Path (Join-Path $Root 'frontend\src\main.tsx'))) {
  throw "Execute na raiz do CloudOS-Unified: $Root"
}

$SourceBackup = Get-ChildItem -Path $Root -Directory -Filter 'backup-core-ui-*' |
  Sort-Object Name -Descending |
  Select-Object -First 1
if (-not $SourceBackup) {
  throw 'Nenhum backup-core-ui-* foi encontrado. Nada foi alterado.'
}

$Stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$Safety = Join-Path $Root "backup-before-rollback-$Stamp"
New-Item -ItemType Directory -Force -Path $Safety | Out-Null

$paths = @(
  'frontend\src\main.tsx',
  'frontend\src\components\Desktop\Desktop.tsx',
  'frontend\public\cloudos-start-menu.js',
  'frontend\index.html'
)

foreach ($rel in $paths) {
  $current = Join-Path $Root $rel
  if (Test-Path $current) {
    $dest = Join-Path $Safety $rel
    New-Item -ItemType Directory -Force -Path (Split-Path $dest) | Out-Null
    Copy-Item $current $dest -Force
  }
}

foreach ($rel in $paths) {
  $saved = Join-Path $SourceBackup.FullName $rel
  if (Test-Path $saved) {
    $dest = Join-Path $Root $rel
    New-Item -ItemType Directory -Force -Path (Split-Path $dest) | Out-Null
    Copy-Item $saved $dest -Force
  }
}

# Remove somente os dois arquivos adicionados pela correcao Core UI.
Remove-Item (Join-Path $Root 'frontend\src\native\shellBridge.ts') -Force -ErrorAction SilentlyContinue
Remove-Item (Join-Path $Root 'frontend\src\native\coreUiFix.css') -Force -ErrorAction SilentlyContinue

Push-Location $Root
try {
  & npm.cmd run lint
  if ($LASTEXITCODE -ne 0) { throw 'Lint falhou depois da reversao.' }
  & npm.cmd run build
  if ($LASTEXITCODE -ne 0) { throw 'Build falhou depois da reversao.' }
  & npm.cmd test
  if ($LASTEXITCODE -ne 0) { throw 'Testes falharam depois da reversao.' }
  Write-Host "Reversao concluida usando: $($SourceBackup.FullName)" -ForegroundColor Green
  Write-Host "Estado anterior a reversao salvo em: $Safety" -ForegroundColor Cyan
} catch {
  Write-Host 'A validacao falhou. Restaurando o estado anterior a reversao...' -ForegroundColor Red
  foreach ($rel in $paths) {
    $saved = Join-Path $Safety $rel
    if (Test-Path $saved) {
      $dest = Join-Path $Root $rel
      New-Item -ItemType Directory -Force -Path (Split-Path $dest) | Out-Null
      Copy-Item $saved $dest -Force
    }
  }
  throw
} finally {
  Pop-Location
}
