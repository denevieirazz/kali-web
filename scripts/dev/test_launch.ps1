$p = Start-Process -FilePath 'desktop\CloudOS.FlutterShell\build\windows\x64\runner\Release\cloudos_flutter_shell.exe' -WorkingDirectory 'desktop\CloudOS.FlutterShell\build\windows\x64\runner\Release' -PassThru
Start-Sleep -Seconds 3
Write-Host "PID: $($p.Id) HasExited: $($p.HasExited)"
if (-not $p.HasExited) {
    Write-Host "MainWindowHandle: $($p.MainWindowHandle)"
    $p.Refresh()
    Write-Host "Refreshed MainWindowHandle: $($p.MainWindowHandle)"
}
