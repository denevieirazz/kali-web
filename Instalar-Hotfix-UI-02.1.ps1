$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$File = Join-Path $Root 'frontend\src\components\StartMenu\StartMenu.tsx'
if (-not (Test-Path $File)) { throw "Execute na raiz do CloudOS-Unified. Arquivo nao encontrado: $File" }
$Stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$Backup = "$File.backup-$Stamp"
Copy-Item $File $Backup -Force
$Text = Get-Content $File -Raw
$Broken = "  const windows = useWindowManager(s => s.windows.filter(w => !w.isSystem));"
$Fixed = "  const allWindows = useWindowManager(s => s.windows);`r`n  const windows = useMemo(() => allWindows.filter(w => !w.isSystem), [allWindows]);"
if ($Text.Contains($Broken)) {
  $Text = $Text.Replace($Broken, $Fixed)
} elseif ($Text -match 'const allWindows = useWindowManager') {
  Write-Host 'O hotfix ja esta aplicado.' -ForegroundColor Yellow
} else {
  throw 'A linha esperada nao foi encontrada. Nada foi alterado.'
}
Set-Content $File $Text -Encoding UTF8
Push-Location $Root
try {
  & npm.cmd run lint
  if ($LASTEXITCODE -ne 0) { throw 'Lint falhou' }
  & npm.cmd run build
  if ($LASTEXITCODE -ne 0) { throw 'Build falhou' }
  & npm.cmd test
  if ($LASTEXITCODE -ne 0) { throw 'Testes falharam' }
  Write-Host 'Hotfix 02.1 instalado. Reinicie o CloudOS.' -ForegroundColor Green
} catch {
  Copy-Item $Backup $File -Force
  Write-Host 'Falha na validacao. StartMenu.tsx restaurado.' -ForegroundColor Red
  throw
} finally {
  Pop-Location
}
