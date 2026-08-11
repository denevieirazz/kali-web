$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$Runtime = Join-Path $Root 'runtime'
$Logs = Join-Path $Root 'logs'
$BackendRuntime = Join-Path $Runtime 'backend-port.json'
$FrontendRuntime = Join-Path $Runtime 'frontend-port.json'
$LauncherLog = Join-Path $Logs 'launcher.log'

New-Item -ItemType Directory -Force -Path $Runtime, $Logs | Out-Null

function Write-LauncherLog([string]$Message) {
  $line = "$(Get-Date -Format o) $Message"
  Add-Content -LiteralPath $LauncherLog -Value $line -Encoding UTF8
  Write-Host $Message
}

function Stop-RuntimeProcess([string]$RuntimeFile) {
  if (-not (Test-Path -LiteralPath $RuntimeFile)) { return }
  try {
    $info = Get-Content -LiteralPath $RuntimeFile -Raw | ConvertFrom-Json
    if ($info.pid) {
      $process = Get-Process -Id ([int]$info.pid) -ErrorAction SilentlyContinue
      if ($process) {
        Stop-Process -Id $process.Id -Force
        $process.WaitForExit(5000)
      }
    }
  } catch {
    Write-LauncherLog "Aviso ao encerrar runtime antigo: $($_.Exception.Message)"
  } finally {
    Remove-Item -LiteralPath $RuntimeFile -Force -ErrorAction SilentlyContinue
  }
}

function Wait-JsonFile([string]$Path, [int]$TimeoutSeconds) {
  $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
  do {
    if (Test-Path -LiteralPath $Path) {
      try { return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json } catch {}
    }
    Start-Sleep -Milliseconds 250
  } while ((Get-Date) -lt $deadline)
  throw "Tempo esgotado aguardando $Path"
}

function Wait-Health([string]$Url, [int]$TimeoutSeconds) {
  $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
  do {
    try {
      $response = Invoke-RestMethod -Uri $Url -TimeoutSec 2
      if ($response.status -eq 'ok') { return }
    } catch {}
    Start-Sleep -Milliseconds 400
  } while ((Get-Date) -lt $deadline)
  throw "Backend nao respondeu em $Url"
}

try {
  Write-LauncherLog 'Iniciando CloudOS-Unified...'
  Stop-RuntimeProcess $FrontendRuntime
  Stop-RuntimeProcess $BackendRuntime

  $backendOut = Join-Path $Logs 'backend.log'
  $backendErr = Join-Path $Logs 'backend-error.log'
  $frontendOut = Join-Path $Logs 'frontend.log'
  $frontendErr = Join-Path $Logs 'frontend-error.log'
  Remove-Item $backendOut,$backendErr,$frontendOut,$frontendErr -Force -ErrorAction SilentlyContinue

  $backend = Start-Process -FilePath 'npm.cmd' -ArgumentList '--prefix','backend','run','dev' -WorkingDirectory $Root -WindowStyle Hidden -RedirectStandardOutput $backendOut -RedirectStandardError $backendErr -PassThru
  Write-LauncherLog "Backend iniciado, PID inicial $($backend.Id)."
  $backendInfo = Wait-JsonFile $BackendRuntime 20
  $backendPort = if ($backendInfo.backendPort) { [int]$backendInfo.backendPort } elseif ($backendInfo.port) { [int]$backendInfo.port } else { throw 'Porta do backend ausente.' }
  Wait-Health "http://127.0.0.1:$backendPort/api/health" 20

  $frontend = Start-Process -FilePath 'npm.cmd' -ArgumentList '--prefix','frontend','run','dev' -WorkingDirectory $Root -WindowStyle Hidden -RedirectStandardOutput $frontendOut -RedirectStandardError $frontendErr -PassThru
  Write-LauncherLog "Frontend iniciado, PID inicial $($frontend.Id)."
  $frontendInfo = Wait-JsonFile $FrontendRuntime 20
  $frontendPort = if ($frontendInfo.port) { [int]$frontendInfo.port } else { throw 'Porta do frontend ausente.' }
  $url = "http://127.0.0.1:$frontendPort"

  $deadline = (Get-Date).AddSeconds(20)
  do {
    try {
      $result = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 2
      if ($result.StatusCode -eq 200) { break }
    } catch {}
    Start-Sleep -Milliseconds 400
  } while ((Get-Date) -lt $deadline)
  if (-not $result -or $result.StatusCode -ne 200) { throw "Frontend nao respondeu em $url" }

  Write-LauncherLog "CloudOS pronto em $url"
  Start-Process $url
  exit 0
} catch {
  Write-LauncherLog "ERRO: $($_.Exception.Message)"
  Write-Host ''
  Write-Host 'Consulte os arquivos na pasta logs.' -ForegroundColor Yellow
  exit 1
}
