[CmdletBinding()]
param(
    [string]$OutputDir
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
$timestamp = (Get-Date).ToString('yyyyMMdd-HHmmss')

if (-not $OutputDir) {
    $OutputDir = Join-Path $env:TEMP "CloudOS-Diagnostics-$timestamp"
}
if (-not (Test-Path -LiteralPath $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
}

Write-Host "[Diagnostics] Gerando pacote de suporte sanitizado CloudOS..." -ForegroundColor Cyan

# Funcao para sanitizar texto
function Sanitize-Text([string]$text) {
    if (-not $text) { return '' }
    $userProfile = $env:USERPROFILE
    $userName = $env:USERNAME
    $clean = $text
    if ($userProfile) {
        $clean = $clean -replace [regex]::Escape($userProfile), '%USERPROFILE%'
    }
    if ($userName) {
        $clean = $clean -replace [regex]::Escape($userName), '<USER>'
    }
    # Remover padroes de chaves ou senhas se houver
    $clean = $clean -replace '(?i)(password|secret|token|apikey)\s*[:=]\s*["''][^"'']+["'']', '$1: [REDACTED]'
    return $clean
}

# 1. Informacoes do Sistema
$sysInfo = [ordered]@{
    timestamp          = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    os                 = [Environment]::OSVersion.VersionString
    osBuild            = [Environment]::OSVersion.Version.Build
    architecture       = $(if ([Environment]::Is64BitOperatingSystem) { 'x64' } else { 'x86' })
    processorCount     = [Environment]::ProcessorCount
    dotNetVersion      = [Environment]::Version.ToString()
    machineName        = '<REDACTED>'
}
$sysInfoJson = $sysInfo | ConvertTo-Json -Depth 4
Set-Content -LiteralPath (Join-Path $OutputDir 'system-info.json') -Value (Sanitize-Text $sysInfoJson) -Encoding UTF8

# 2. Gate 0 & Recovery Status
$recoveryExe = Join-Path $repoRoot 'desktop\CloudOS.NativeShell\bin\Release\CloudOS.Recovery.exe'
if (Test-Path -LiteralPath $recoveryExe) {
    try {
        $recStatus = & $recoveryExe status
        Set-Content -LiteralPath (Join-Path $OutputDir 'recovery-status.json') -Value (Sanitize-Text $recStatus) -Encoding UTF8
    } catch {
        Set-Content -LiteralPath (Join-Path $OutputDir 'recovery-status.json') -Value "Erro ao coletar status: $_" -Encoding UTF8
    }
}

# 3. SystemBroker Self-Test Status
$brokerExe = Join-Path $repoRoot 'desktop\CloudOS.NativeShell\bin\Release\CloudOS.SystemBroker.exe'
if (Test-Path -LiteralPath $brokerExe) {
    try {
        $brokerSelfTest = & $brokerExe --self-test
        Set-Content -LiteralPath (Join-Path $OutputDir 'broker-selftest.txt') -Value (Sanitize-Text ($brokerSelfTest -join "`r`n")) -Encoding UTF8
    } catch { }
}

# 4. Logs do Instalador e Manutencao
$installerLogs = Join-Path $env:LOCALAPPDATA 'CloudOS\InstallerLogs'
if (Test-Path -LiteralPath $installerLogs) {
    $destLogs = Join-Path $OutputDir 'installer-logs'
    New-Item -ItemType Directory -Path $destLogs -Force | Out-Null
    $logFiles = Get-ChildItem -Path $installerLogs -Filter '*.log' | Sort-Object LastWriteTime -Descending | Select-Object -First 5
    foreach ($lf in $logFiles) {
        $raw = Get-Content -LiteralPath $lf.FullName -Raw -ErrorAction SilentlyContinue
        if ($raw) {
            Set-Content -LiteralPath (Join-Path $destLogs $lf.Name) -Value (Sanitize-Text $raw) -Encoding UTF8
        }
    }
}

# 5. Manifestos do Runtime
foreach ($m in @('version.json', 'cloudos-native-manifest.json', 'cloudos-v21-integrated-manifest.json')) {
    $mPath = Join-Path $repoRoot $m
    if (-not (Test-Path -LiteralPath $mPath)) {
        $mPath = Join-Path $repoRoot "desktop\CloudOS.NativeShell\bin\Release\$m"
    }
    if (-not (Test-Path -LiteralPath $mPath)) {
        $mPath = Join-Path $repoRoot "desktop\CloudOS.FlutterShell\build\windows\x64\runner\Release\$m"
    }
    if (Test-Path -LiteralPath $mPath) {
        $rawM = Get-Content -LiteralPath $mPath -Raw -ErrorAction SilentlyContinue
        Set-Content -LiteralPath (Join-Path $OutputDir $m) -Value (Sanitize-Text $rawM) -Encoding UTF8
    }
}

# 6. Preferencias (Sanitizadas)
$prefsFile = Join-Path $env:LOCALAPPDATA 'CloudOS\preferences-v1.json'
if (Test-Path -LiteralPath $prefsFile) {
    $rawPrefs = Get-Content -LiteralPath $prefsFile -Raw -ErrorAction SilentlyContinue
    if ($rawPrefs) {
        Set-Content -LiteralPath (Join-Path $OutputDir 'preferences.sanitized.json') -Value (Sanitize-Text $rawPrefs) -Encoding UTF8
    }
}

# 7. Empacotar ZIP final
$zipPath = Join-Path (Split-Path -Parent $OutputDir) "CloudOS-Diagnostics-$timestamp.zip"
if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }

Compress-Archive -Path (Join-Path $OutputDir '*') -DestinationPath $zipPath -CompressionLevel Optimal
Write-Host "  [OK] Pacote gerado com sucesso: $zipPath" -ForegroundColor Green

return [pscustomobject]@{
    ZipPath   = $zipPath
    ReportDir = $OutputDir
    Timestamp = $timestamp
}
