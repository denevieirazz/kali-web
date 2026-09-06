$data = Import-Csv 'docs\qa-data\rc14-soak.csv'
$processes = $data | Select-Object -ExpandProperty ProcessName -Unique
Write-Host "Soak Analysis Summary (Samples: $($data.Count), Timespan: $($data[0].Timestamp) to $($data[-1].Timestamp)):"
foreach ($proc in $processes) {
    $rows = @($data | Where-Object { $_.ProcessName -eq $proc })
    if ($rows.Count -gt 0) {
        $first = $rows[0]
        $last = $rows[-1]
        $wsFirst = [double]$first.WorkingSet_MB
        $wsLast = [double]$last.WorkingSet_MB
        $pbFirst = [double]$first.PrivateBytes_MB
        $pbLast = [double]$last.PrivateBytes_MB
        $hFirst = [int]$first.Handles
        $hLast = [int]$last.Handles
        $wsDelta = [math]::Round($wsLast - $wsFirst, 2)
        $pbDelta = [math]::Round($pbLast - $pbFirst, 2)
        $hDelta = $hLast - $hFirst
        Write-Host "Process: $proc (Samples: $($rows.Count))"
        Write-Host "  WorkingSet:   T0=$wsFirst MB -> Tend=$wsLast MB (Delta: $wsDelta MB)"
        Write-Host "  PrivateBytes: T0=$pbFirst MB -> Tend=$pbLast MB (Delta: $pbDelta MB)"
        Write-Host "  Handles:      T0=$hFirst -> Tend=$hLast (Delta: $hDelta)"
    }
}
