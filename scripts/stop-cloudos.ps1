$ErrorActionPreference = 'Continue'
$hosts = @(Get-Process -Name 'CloudOS.Host' -ErrorAction SilentlyContinue)
if (-not $hosts.Count) {
  Write-Host 'Nenhuma janela CloudOS.Host está ativa.'
  exit 0
}

foreach ($hostProcess in $hosts) {
  if ($hostProcess.MainWindowHandle -ne 0) {
    [void]$hostProcess.CloseMainWindow()
    Write-Host "Encerramento gracioso solicitado ao CloudOS PID=$($hostProcess.Id)."
  }
}

Write-Host 'O script não força processos nem confia em PIDs de arquivos runtime.'
