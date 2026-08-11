$ErrorActionPreference = 'Continue'
$Root = Split-Path -Parent $PSScriptRoot
$Runtime = Join-Path $Root 'runtime'
foreach ($name in 'frontend-port.json','backend-port.json') {
  $file = Join-Path $Runtime $name
  if (Test-Path -LiteralPath $file) {
    try {
      $info = Get-Content -LiteralPath $file -Raw | ConvertFrom-Json
      if ($info.pid) { Stop-Process -Id ([int]$info.pid) -Force -ErrorAction SilentlyContinue }
    } catch {}
    Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue
  }
}
Write-Host 'CloudOS encerrado.'
