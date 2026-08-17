param([ValidateRange(1,60)][int]$TimeoutSeconds=10)
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'

$names=@('CloudOS.Host','CloudOS.Bootstrap','CloudOS.WslCore')
$targets=New-Object System.Collections.Generic.List[object]
foreach($name in $names){foreach($process in @(Get-Process -Name $name -ErrorAction SilentlyContinue)){[void]$targets.Add($process)}}
if($targets.Count -eq 0){Write-Host 'Nenhum processo do CloudOS estava em execução.';exit 0}
$watch=[Diagnostics.Stopwatch]::StartNew()
foreach($process in $targets){
    try{
        if(-not $process.HasExited -and $process.MainWindowHandle -ne 0){[void]$process.CloseMainWindow()}
    }catch{Write-Verbose "Falha ao solicitar encerramento de $($process.ProcessName):$($process.Id): $($_.Exception.Message)"}
}
$deadline=[DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
do{
    $remaining=@($targets|Where-Object{try{$_.Refresh();-not $_.HasExited}catch{$false}})
    if($remaining.Count -eq 0){break}
    Start-Sleep -Milliseconds 200
}while([DateTime]::UtcNow -lt $deadline)
$watch.Stop()
$remaining=@($targets|Where-Object{try{$_.Refresh();-not $_.HasExited}catch{$false}})
foreach($process in $targets){try{$process.Dispose()}catch{}}
if($remaining.Count -gt 0){
    Write-Error 'O CloudOS não encerrou completamente dentro do tempo esperado. Execute os diagnósticos antes de tentar novamente.'
    exit 1
}
Write-Host "CLOUDOS_SHUTDOWN_OK processes=$($targets.Count) elapsedMs=$($watch.ElapsedMilliseconds) orphans=false"
