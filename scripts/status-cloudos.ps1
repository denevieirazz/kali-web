$Root = Split-Path -Parent $PSScriptRoot
$Runtime = Join-Path $Root 'runtime'
foreach ($name in 'backend-port.json','frontend-port.json') {
  $file = Join-Path $Runtime $name
  if (-not (Test-Path -LiteralPath $file)) { Write-Host "$name: ausente"; continue }
  try {
    $info = Get-Content -LiteralPath $file -Raw | ConvertFrom-Json
    $process = if ($info.pid) { Get-Process -Id ([int]$info.pid) -ErrorAction SilentlyContinue } else { $null }
    $state = if ($process) { 'ativo' } else { 'inativo' }
    Write-Host "$name: $state PID=$($info.pid) URL=$($info.url)"
  } catch { Write-Host "$name: invalido" }
}
