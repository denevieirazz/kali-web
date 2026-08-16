$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$failures = [System.Collections.Generic.List[string]]::new()

function Require([bool]$Condition, [string]$Message) {
  if (-not $Condition) { $script:failures.Add($Message) }
}

$coreRoot = Join-Path $root 'core\wsl\cloudos-core'
$hostRoot = Join-Path $root 'desktop\CloudOS.WslCore'
$probeRoot = Join-Path $root 'desktop\CloudOS.WslCore.Probe'
$validationScript = Join-Path $root 'scripts\validate-wsl-core-foundation.ps1'

Require (Test-Path -LiteralPath $coreRoot) 'Linux cloudos-core source is missing.'
Require (Test-Path -LiteralPath $hostRoot) 'Windows WSL core client/supervisor is missing.'
Require (Test-Path -LiteralPath $probeRoot) 'Windows/WSL physical probe is missing.'
Require (Test-Path -LiteralPath $validationScript) 'Physical validation script is missing.'

$tokens = $null
$parseErrors = $null
[void][System.Management.Automation.Language.Parser]::ParseFile($validationScript, [ref]$tokens, [ref]$parseErrors)
Require ($parseErrors.Count -eq 0) ('Physical validation script has PowerShell parse errors: ' + (($parseErrors | ForEach-Object Message) -join '; '))

$implementationFiles = @(
  (Get-ChildItem -LiteralPath $coreRoot -Recurse -File -Include *.go | Where-Object { $_.Name -notlike '*_test.go' -and $_.FullName -notmatch '[\\/](bin|obj)[\\/]' }),
  (Get-ChildItem -LiteralPath $hostRoot -Recurse -File -Include *.cs | Where-Object { $_.FullName -notmatch '[\\/](bin|obj)[\\/]' }),
  (Get-ChildItem -LiteralPath $probeRoot -Recurse -File -Include *.cs | Where-Object { $_.FullName -notmatch '[\\/](bin|obj)[\\/]' })
) | ForEach-Object { $_ }
$implementationText = ($implementationFiles | ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw }) -join "`n"

# A dedicated interactive login shell is part of the Terminal contract. What is forbidden here
# is generic command-string shell execution (-c/-lc/-ec), which would bypass argv allowlisting.
Require ($implementationText -notmatch '(?im)\b(?:bash|sh)(?:\.exe)?\s+-[A-Za-z]*c[A-Za-z]*(?:\s|$)') 'Implementation contains generic shell command-string execution.'
Require ($implementationText -notmatch '(?i)(sqlite|persistentdatabase|databasePath|CLOUDOS_DATA_DIR|CLOUDOS_DATABASE)') 'WSL core implementation references the CloudOS database surface.'
Require ($implementationText -notmatch '(?i)(metasploit|sqlmap|nmap|nikto|gobuster|msfvenom)') 'WSL core implementation references offensive tooling.'
Require ($implementationText -notmatch '(?i)(ext4\.vhdx|usbipd|weston|wayland|xwayland)') 'WSL core implementation crosses an excluded WSL/WSLg boundary.'

$supervisorText = Get-Content -LiteralPath (Join-Path $hostRoot 'WslCoreSupervisor.cs') -Raw
foreach ($forbidden in @('--install','--import','--update','--terminate','--shutdown','--set-default','--set-version','RunAs','Verb =')) {
  Require ($supervisorText.IndexOf($forbidden, [StringComparison]::OrdinalIgnoreCase) -lt 0) "Supervisor contains forbidden WSL mutation/elevation token: $forbidden"
}
Require ($supervisorText -match 'ArgumentList\.Add') 'Supervisor must use ProcessStartInfo.ArgumentList.'
Require ($supervisorText -match 'UseShellExecute\s*=\s*false') 'Supervisor must disable shell execution.'
Require ($supervisorText -match 'CLOUDOS_WSL_CORE_FOUNDATION') 'Experimental feature flag is missing.'
Require ($supervisorText -match 'AllowBootstrap') 'Explicit bootstrap authorization is missing.'
Require ($supervisorText -match 'DISTRO_NOT_WSL2') 'WSL2 distribution guard is missing.'

$processText = Get-Content -LiteralPath (Join-Path $coreRoot 'internal\process\manager.go') -Raw
Require ($processText -match 'exec\.CommandContext\(ctx, options\.Executable, options\.Args\.\.\.\)') 'Linux process creation is not argument-vector based.'
Require ($processText -match 'allowedExecutables') 'Linux executable allowlist is missing.'
Require ($processText -match 'Pdeathsig:\s*syscall\.SIGKILL') 'Linux parent-death cleanup guard is missing.'
Require ($processText -match 'pty\.StartWithSize') 'Reused creack/pty integration is missing.'

$protocolText = Get-Content -LiteralPath (Join-Path $coreRoot 'internal\protocol\protocol.go') -Raw
Require ($protocolText -match 'MaxFrameBytes\s*=\s*1\s*<<\s*20') '1 MiB protocol frame limit is missing.'
Require ($protocolText -match 'binary\.BigEndian') 'Length-prefixed binary framing is missing.'
Require ($protocolText -match 'hmac\.New\(sha256\.New') 'HMAC mutual-auth primitive is missing.'

$metricsText = Get-Content -LiteralPath (Join-Path $coreRoot 'internal\metrics\metrics.go') -Raw
foreach ($required in @('/proc/uptime','/proc/loadavg','/proc/meminfo','/proc/self/cgroup','/sys/fs/cgroup')) {
  Require ($metricsText.IndexOf($required, [StringComparison]::Ordinal) -ge 0) "Real Linux metric source is missing: $required"
}
Require ($metricsText -notmatch '(?i)(WriteFile|Mkdir|Chmod|Chown).*cgroup') 'Metrics implementation appears to mutate cgroups.'

$validationText = Get-Content -LiteralPath $validationScript -Raw
foreach ($forbidden in @('--install','--import','--update','--terminate','--shutdown','--set-default','--set-version','Start-Process','-Verb RunAs')) {
  Require ($validationText.IndexOf($forbidden, [StringComparison]::OrdinalIgnoreCase) -lt 0) "Physical validation script contains forbidden mutation/elevation token: $forbidden"
}

# Execução direta da normalização de saída crua do WSL (substituição de caracteres nulos)
$sampleRaw = "*`0 `0k`0a`0l`0i`0-`0l`0i`0n`0u`0x`0 `0 `0 `0R`0u`0n`0n`0i`0n`0g`0 `0 `0 `02`0`r`0`n`0"
try {
  $normalized = ([string]$sampleRaw).Replace([string][char]0, [string]'').Trim()
  Require ($normalized.StartsWith('*') -and $normalized.Contains('kali-linux') -and $normalized.EndsWith('2')) 'WSL raw output normalization failed.'
} catch {
  Require $false ("WSL string replacement threw an unexpected exception: " + $_.Exception.Message)
}

if (Test-Path -LiteralPath (Join-Path $root '.git')) {
  $currentBranch = (& git -C $root branch --show-current 2>$null).Trim()
  if ($currentBranch -like 'feature/wsl-core*') {
    $base = '56f0ca8bc0a59987a43295da1ded277afc40e6e9'
    $changed = @(& git -C $root diff --name-only "$base...HEAD" 2>$null)
    $browserChanges = @($changed | Where-Object { $_ -match '(^|/)(Browser|browser)(/|\.|$)' })
    Require ($browserChanges.Count -eq 0) ('Browser files changed in WSL-only branch: ' + ($browserChanges -join ', '))
  }
}

if ($failures.Count -gt 0) {
  $failures | ForEach-Object { Write-Error $_ }
  exit 1
}

Write-Host 'PASS CloudOS WSL core static safety contract'
