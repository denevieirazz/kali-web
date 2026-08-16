[CmdletBinding()]
param(
  [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]{0,79}$')][string]$Distribution,
  [switch]$AllowLegacyFallback
)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'visible-terminal-wsl-core-common.ps1')
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$wsl=Join-Path ($env:WINDIR ?? 'C:\Windows') 'System32\wsl.exe'
if(-not(Test-Path -LiteralPath $wsl)){throw 'WSL_NOT_FOUND'}
$node=(Get-Command node -ErrorAction Stop).Source
$selected=Get-CloudOSWsl2Distribution -WslExe $wsl -Requested $Distribution
$runId=[Guid]::NewGuid().ToString('N')
$core=$null;$backend=$null;$frontend=$null
$temp=Join-Path ([IO.Path]::GetTempPath()) "cloudos-visible-terminal-dev-$runId"
$runtime=Join-Path $temp 'runtime';$data=Join-Path $temp 'data'
New-Item -ItemType Directory -Force -Path $runtime,$data | Out-Null
try {
  $core=New-CloudOSTemporaryCore -Root $root -WslExe $wsl -Distribution $selected -RunId $runId
  $frontPort=Get-CloudOSFreePort
  $fallbackValue=if($AllowLegacyFallback){'1'}else{'0'}
  $envMap=@{
    NODE_ENV='development'; CLOUDOS_WSL_CORE_FOUNDATION='1'; CLOUDOS_WSL_CORE_TERMINAL='1';
    CLOUDOS_WSL_CORE_TERMINAL_FALLBACK=$fallbackValue; CLOUDOS_WSL_CORE_LINUX_PATH=$core.Path;
    CLOUDOS_RUNTIME_DIR=$runtime; CLOUDOS_DATA_DIR=$data; DATABASE_PATH=(Join-Path $data 'cloudos.json'); PORT='0';
    CLOUDOS_FRONTEND_PORT=[string]$frontPort; CLOUDOS_FRONTEND_STRICT_PORT='1'; CORS_ORIGIN="http://127.0.0.1:$frontPort"
  }
  $backend=Start-CloudOSNodeProcess -NodeExe $node -Script (Join-Path $root 'backend\src\server.js') -WorkingDirectory (Join-Path $root 'backend') -Environment $envMap
  [void](Wait-CloudOSJsonFile -Path (Join-Path $runtime 'backend-port.json'))
  $frontend=Start-CloudOSNodeProcess -NodeExe $node -Script (Join-Path $root 'frontend\scripts\dev-server.js') -WorkingDirectory (Join-Path $root 'frontend') -Environment $envMap
  $frontRuntime=Wait-CloudOSJsonFile -Path (Join-Path $runtime 'frontend-port.json')
  Write-Host 'CloudOS Terminal v2 DEV' -ForegroundColor Cyan
  Write-Host "Linux: $selected" -ForegroundColor Green
  Write-Host "WSL Core v2: ativado | fallback: $(if($AllowLegacyFallback){'permitido'}else{'desligado'})" -ForegroundColor Green
  Write-Host 'Dados: temporários e isolados' -ForegroundColor Green
  Start-Process $frontRuntime.url
  Write-Host 'Pressione Ctrl+C para encerrar somente os processos desta sessão.' -ForegroundColor Yellow
  while($true){ Start-Sleep -Seconds 1; if($backend.HasExited -or $frontend.HasExited){throw 'DEV_PROCESS_EXITED'} }
} finally {
  Stop-CloudOSOwnedProcess $frontend; Stop-CloudOSOwnedProcess $backend
  if($core){Remove-CloudOSTemporaryCore -WslExe $wsl -Distribution $selected -Core $core}
  Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
}
