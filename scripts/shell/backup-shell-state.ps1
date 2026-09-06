param(
    [string]$DestinationPath = (Join-Path $env:LOCALAPPDATA 'CloudOS\Recovery\shell-backup.json')
)

$ErrorActionPreference = 'Stop'

$recDir = Split-Path -Parent $DestinationPath
if (-not (Test-Path -LiteralPath $recDir)) {
    New-Item -ItemType Directory -Path $recDir -Force | Out-Null
}

$userSid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$sessionId = [System.Diagnostics.Process]::GetCurrentProcess().SessionId

$hklmWinlogon = Get-ItemProperty -Path 'HKLM:\Software\Microsoft\Windows NT\CurrentVersion\Winlogon' -ErrorAction SilentlyContinue
$hklmShell = if ($hklmWinlogon -and $hklmWinlogon.PSObject.Properties['Shell']) { [string]$hklmWinlogon.Shell } else { 'explorer.exe' }
$hklmUserinit = if ($hklmWinlogon -and $hklmWinlogon.PSObject.Properties['Userinit']) { [string]$hklmWinlogon.Userinit } else { 'C:\WINDOWS\system32\userinit.exe,' }

$hkcuPolicy = Get-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\System' -ErrorAction SilentlyContinue
$hkcuPolicyShell = if ($hkcuPolicy -and $hkcuPolicy.PSObject.Properties['Shell']) { [string]$hkcuPolicy.Shell } else { $null }

$hkcuWinlogon = Get-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Winlogon' -ErrorAction SilentlyContinue
$hkcuWinlogonShell = if ($hkcuWinlogon -and $hkcuWinlogon.PSObject.Properties['Shell']) { [string]$hkcuWinlogon.Shell } else { $null }

$installDir = Join-Path $env:LOCALAPPDATA 'Programs\CloudOS'
$startupKey = Get-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -ErrorAction SilentlyContinue
$startupCmd = if ($startupKey -and $startupKey.PSObject.Properties['CloudOS']) { [string]$startupKey.CloudOS } else { $null }

$backup = [ordered]@{
    backup_version = 1
    created_utc = [DateTime]::UtcNow.ToString('o')
    windows_caption = (Get-CimInstance Win32_OperatingSystem).Caption
    windows_edition = 'Windows 11 Pro'
    windows_build = [Environment]::OSVersion.Version.Build
    architecture = 'x64'
    user_sid = $userSid
    session_id = $sessionId
    original_hklm_shell = $hklmShell
    original_userinit = $hklmUserinit
    original_hkcu_policy_shell = $hkcuPolicyShell
    original_hkcu_winlogon_shell = $hkcuWinlogonShell
    cloudos_install_dir = $installDir
    cloudos_startup_command = $startupCmd
    cloudos_version = '21.0.0'
}

$json = $backup | ConvertTo-Json -Depth 5
[System.IO.File]::WriteAllText($DestinationPath, $json, [System.Text.Encoding]::UTF8)

Write-Output $DestinationPath
