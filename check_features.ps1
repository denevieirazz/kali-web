$w = (Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux).State
$v = (Get-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform).State
Write-Host "WSL_FEATURE: $w"
Write-Host "VMP_FEATURE: $v"

$rebootPending = Test-Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending"
Write-Host "REBOOT_PENDING: $rebootPending"

try {
    $distros = wsl.exe -l -v
    Write-Host "WSL_DISTROS:"
    $distros | ForEach-Object { Write-Host $_ }
} catch {
    Write-Host "WSL_DISTROS_ERROR: $($_.Exception.Message)"
}
