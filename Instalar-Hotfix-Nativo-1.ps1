$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$Main = Join-Path $Root 'frontend\src\main.tsx'
$Native = Join-Path $Root 'frontend\src\native'
$Stores = Join-Path $Root 'frontend\src\stores'
if (-not (Test-Path $Main)) { throw "Execute na raiz do CloudOS-Unified: $Root" }
$Stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$Backup = Join-Path $Root "backup-native-hotfix-$Stamp"
New-Item -ItemType Directory -Force -Path $Backup | Out-Null
foreach ($rel in @('frontend\src\main.tsx','frontend\src\native\applyShellSettings.ts','frontend\src\native\nativeHotfix.css')) {
  $source = Join-Path $Root $rel
  if (Test-Path $source) { $dest = Join-Path $Backup $rel; New-Item -ItemType Directory -Force -Path (Split-Path $dest) | Out-Null; Copy-Item $source $dest -Force }
}
New-Item -ItemType Directory -Force -Path $Native | Out-Null
New-Item -ItemType Directory -Force -Path $Stores | Out-Null
Copy-Item (Join-Path $Root 'payload\frontend\src\stores-settingsStore.ts') (Join-Path $Stores 'settingsStore.ts') -Force
Copy-Item (Join-Path $Root 'payload\frontend\src\native\applyShellSettings.ts') (Join-Path $Native 'applyShellSettings.ts') -Force
Copy-Item (Join-Path $Root 'payload\frontend\src\native\nativeHotfix.css') (Join-Path $Native 'nativeHotfix.css') -Force
$text = Get-Content $Main -Raw
if ($text -notmatch "native/nativeHotfix.css") { $text = "import './native/nativeHotfix.css';`r`n" + $text; Set-Content $Main $text -Encoding UTF8 }
Push-Location $Root
try {
  & npm.cmd run lint; if ($LASTEXITCODE -ne 0) { throw 'Lint falhou' }
  & npm.cmd run build; if ($LASTEXITCODE -ne 0) { throw 'Build falhou' }
  & npm.cmd test; if ($LASTEXITCODE -ne 0) { throw 'Testes falharam' }
  Write-Host "Hotfix instalado. Backup: $Backup" -ForegroundColor Green
} finally { Pop-Location }
