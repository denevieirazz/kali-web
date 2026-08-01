$logPath = "C:\Users\dougl\ram_monitor_log.txt"
"=== MONITOR DE MEMORIA E SISTEMA INICIADO EM $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ===" | Out-File -FilePath $logPath -Encoding utf8

while ($true) {
    try {
        $date = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $os = Get-CimInstance Win32_OperatingSystem
        $totalRamMb = [math]::Round($os.TotalVisibleMemorySize / 1024, 2)
        $freeRamMb = [math]::Round($os.FreePhysicalMemory / 1024, 2)
        $usedRamMb = [math]::Round($totalRamMb - $freeRamMb, 2)
        $ramPercent = [math]::Round(($usedRamMb / $totalRamMb) * 100, 1)

        $totalVirtMb = [math]::Round($os.TotalVirtualMemorySize / 1024, 2)
        $freeVirtMb = [math]::Round($os.FreeVirtualMemory / 1024, 2)
        $usedVirtMb = [math]::Round($totalVirtMb - $freeVirtMb, 2)
        $virtPercent = [math]::Round(($usedVirtMb / $totalVirtMb) * 100, 1)

        $topProcs = Get-Process | Sort-Object WorkingSet64 -Descending | Select-Object -First 7 Name, Id, @{N='WorkingSetMB';E={[math]::Round($_.WorkingSet64/1MB,1)}}

        $procStr = ($topProcs | ForEach-Object { "$($_.Name)(PID:$($_.Id))=$($_.WorkingSetMB)MB" }) -join " | "

        $logLine = "[$date] RAM: ${usedRamMb}MB/${totalRamMb}MB (${ramPercent}%) | VIRT: ${usedVirtMb}MB/${totalVirtMb}MB (${virtPercent}%) | PROCS: $procStr"
        $logLine | Out-File -FilePath $logPath -Append -Encoding utf8
    } catch {
        "[$date] ERROR: $($_.Exception.Message)" | Out-File -FilePath $logPath -Append -Encoding utf8
    }
    Start-Sleep -Seconds 1
}
