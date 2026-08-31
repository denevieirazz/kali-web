$script:PerformanceNamesV12 = @('desktop_paint','taskbar_paint','start_paint','quick_paint','notification_card_paint','desktop_full_paint','taskbar_full_paint','refresh_shell','reconcile','filesystem_scan','icon_load','icon_load_in_paint','backbuffer_allocation','start_open_us','quick_open_us')
function Get-CloudOSPerformanceV12([int]$ProcessId) {
    $mapping=$null; $view=$null
    try {
        $mapping=[IO.MemoryMappedFiles.MemoryMappedFile]::OpenExisting("Local\CloudOS.Performance.V12.$ProcessId",[IO.MemoryMappedFiles.MemoryMappedFileRights]::Read)
        $view=$mapping.CreateViewAccessor(0,224,[IO.MemoryMappedFiles.MemoryMappedFileAccess]::Read)
        if($view.ReadUInt64(0) -ne 12 -or $view.ReadUInt64(8) -ne $ProcessId) { throw 'Performance ABI mismatch' }
        $result=[ordered]@{heartbeat_tick_ms=$view.ReadUInt64(16)}
        for($i=0;$i -lt 15;$i++) { $result[$script:PerformanceNamesV12[$i]]=$view.ReadInt64(24+$i*8) }
        for($i=0;$i -lt 5;$i++) {
            $result[$script:PerformanceNamesV12[$i]+'_total_us']=$view.ReadInt64(144+$i*8)
            $result[$script:PerformanceNamesV12[$i]+'_max_us']=$view.ReadInt64(184+$i*8)
        }
        return [pscustomobject]$result
    } finally { if($view){$view.Dispose()}; if($mapping){$mapping.Dispose()} }
}
