$hosts = @(Get-Process -Name 'CloudOS.Host' -ErrorAction SilentlyContinue)
if (-not $hosts.Count) {
  Write-Host 'CloudOS.Host: inativo'
  exit 0
}

foreach ($hostProcess in $hosts) {
  Write-Host "CloudOS.Host: ativo PID=$($hostProcess.Id) iniciado=$($hostProcess.StartTime.ToString('o'))"
}
