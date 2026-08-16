$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$failures = [System.Collections.Generic.List[string]]::new()
function Require([bool]$Condition, [string]$Message) { if (-not $Condition) { $script:failures.Add($Message) } }

$coreRoot = Join-Path $root 'core\wsl\cloudos-core'
$hostRoot = Join-Path $root 'desktop\CloudOS.WslCore'
$terminalAdapter = Join-Path $root 'backend\src\terminal\wslCoreAdapter.js'
$terminalSocket = Join-Path $root 'backend\src\terminal\websocket.js'
$validationScript = Join-Path $root 'scripts\validate-wsl-core-secure-terminal.ps1'
$nodeProbe = Join-Path $root 'scripts\probe-wsl-core-terminal.mjs'

foreach ($path in @($coreRoot,$hostRoot,$terminalAdapter,$terminalSocket,$validationScript,$nodeProbe)) {
  Require (Test-Path -LiteralPath $path) "Required secure Terminal component is missing: $path"
}

$tokens = $null; $parseErrors = $null
[void][System.Management.Automation.Language.Parser]::ParseFile($validationScript, [ref]$tokens, [ref]$parseErrors)
Require ($parseErrors.Count -eq 0) ('Physical validation script has PowerShell parse errors: ' + (($parseErrors | ForEach-Object Message) -join '; '))

$protocolGo = Get-Content -LiteralPath (Join-Path $coreRoot 'internal\protocol\protocol.go') -Raw
Require ($protocolGo -match 'Version\s*=\s*2') 'Linux protocol is not v2.'
Require ($protocolGo -match 'aes\.NewCipher') 'Linux protected channel does not use AES.'
Require ($protocolGo -match 'cipher\.NewGCMWithTagSize') 'Linux protected channel does not use GCM.'
Require ($protocolGo -match 'cloudos-core/v2/c2s/key') 'Linux HKDF direction key label is missing.'
Require ($protocolGo -match 'seq\s*!=\s*c\.readSeq\+1') 'Linux exact sequence guard is missing.'
Require ($protocolGo -match 'ErrIntegrity') 'Linux integrity failure path is missing.'

$protocolCs = Get-Content -LiteralPath (Join-Path $hostRoot 'WslCoreProtocol.cs') -Raw
Require ($protocolCs -match 'Version\s*=\s*2') 'Windows protocol is not v2.'
Require ($protocolCs -match 'AesGcm') 'Windows protected channel does not use AES-GCM.'
Require ($protocolCs -match 'FRAME_INTEGRITY') 'Windows integrity failure code is missing.'
Require ($protocolCs -match 'FRAME_SEQUENCE') 'Windows sequence/replay failure code is missing.'
Require ($protocolCs -match 'cloudos-core/v2/c2s/key') 'Windows HKDF direction key label is missing.'

$processText = Get-Content -LiteralPath (Join-Path $coreRoot 'internal\process\manager.go') -Raw
$allowlistMatch = [regex]::Match($processText, 'var allowedExecutables\s*=\s*map\[string\]struct\{\}\s*\{(?<body>.*?)\n\}', [Text.RegularExpressions.RegexOptions]::Singleline)
Require $allowlistMatch.Success 'Generic executable allowlist was not found.'
if ($allowlistMatch.Success) {
  Require ($allowlistMatch.Groups['body'].Value -notmatch '(?i)(bash|/bin/sh|python|nmap|sqlmap|metasploit|msfvenom|nikto|gobuster)') 'Generic executable allowlist was widened to shell/offensive tooling.'
}
Require ($processText -match 'func \(m \*Manager\) CreateTerminal') 'Dedicated fixed Terminal creator is missing.'
Require ($processText -match 'Executable:\s*"/bin/bash"') 'Dedicated Terminal is not pinned to /bin/bash.'
Require ($processText -match 'Args:\s*\[\]string\{"-l"\}') 'Dedicated Terminal is not pinned to login-shell argv.'
Require ($processText -match 'TERMINAL_SESSION_LIMIT') 'One-Terminal-per-connection guard is missing.'
Require ($processText -match 'Pdeathsig:\s*syscall\.SIGKILL') 'Parent-death cleanup guard is missing.'
Require ($processText -match 'syscall\.Kill\(-process\.Pid') 'PTY signals are not sent to the process group.'

$serverText = Get-Content -LiteralPath (Join-Path $coreRoot 'internal\server\server.go') -Raw
Require ($serverText -match 'case "terminal\.create"') 'Server terminal.create method is missing.'
Require ($serverText -match 'manager\.CreateTerminal\(owner, terminal\.Rows, terminal\.Cols\)') 'terminal.create accepts more than fixed size parameters or bypasses fixed creator.'
Require ($serverText -match 'channel\.Read\(\)') 'Post-handshake server traffic is not read from protected channel.'
Require ($serverText -match 'channel\.Write') 'Post-handshake server traffic is not written through protected channel.'

$adapterText = Get-Content -LiteralPath $terminalAdapter -Raw
foreach ($required in @('createCipheriv','createDecipheriv','aes-256-gcm','FRAME_SEQUENCE','FRAME_INTEGRITY','CLOUDOS_WSL_CORE_TERMINAL','CLOUDOS_WSL_CORE_TERMINAL_FALLBACK','terminal.create','--distribution','--exec')) {
  Require ($adapterText.IndexOf($required, [StringComparison]::Ordinal) -ge 0) "Node WSL core adapter is missing contract token: $required"
}
Require ($adapterText -match 'shell:\s*false') 'Node WSL bootstrap does not explicitly disable shell execution.'
Require ($adapterText -notmatch '(?i)(nmap|sqlmap|metasploit|msfvenom|nikto|gobuster)') 'Node WSL core adapter references offensive tooling.'
Require ($adapterText -notmatch '(?i)(sqlite|CLOUDOS_DATA_DIR|CLOUDOS_DATABASE|databasePath)') 'Node WSL core adapter references database state.'

$socketText = Get-Content -LiteralPath $terminalSocket -Raw
Require ($socketText -match 'createWslCoreTerminalSession') 'Existing Terminal WebSocket is not integrated with WSL core adapter.'
Require ($socketText -match "backendMode = 'wsl-core-v2'") 'Terminal does not expose the WSL core backend mode.'
Require ($socketText -match 'wslCoreTerminalFallbackEnabled') 'Legacy fallback is not explicitly feature-gated.'
Require ($socketText -match "backendMode = 'legacy-pty'") 'Legacy PTY fallback path was removed.'
Require ($socketText -match "backendMode = 'emulator'") 'Existing node-pty-unavailable emulator fallback was removed.'

$implementationText = @($protocolGo,$protocolCs,$processText,$serverText,$adapterText) -join "`n"
Require ($implementationText -notmatch '(?i)(metasploit|sqlmap|nmap|nikto|gobuster|msfvenom)') 'Secure WSL core implementation references offensive tooling.'
Require ($implementationText -notmatch '(?i)(ext4\.vhdx|usbipd|weston|wayland|xwayland)') 'Secure WSL core implementation crosses excluded WSL/WSLg boundaries.'
Require ($implementationText -notmatch '(?i)(sqlite|persistentdatabase|CLOUDOS_DATA_DIR|CLOUDOS_DATABASE)') 'Secure WSL core implementation references CloudOS database surface.'

$supervisorText = Get-Content -LiteralPath (Join-Path $hostRoot 'WslCoreSupervisor.cs') -Raw
$validationText = Get-Content -LiteralPath $validationScript -Raw
foreach ($textAndName in @(@($supervisorText,'Supervisor'),@($adapterText,'Node adapter'),@($validationText,'Physical validator'))) {
  $text = $textAndName[0]; $name = $textAndName[1]
  foreach ($forbidden in @('--install','--import','--update','--terminate','--shutdown','--set-default','--set-version','-Verb RunAs')) {
    Require ($text.IndexOf($forbidden, [StringComparison]::OrdinalIgnoreCase) -lt 0) "$name contains forbidden WSL mutation/elevation token: $forbidden"
  }
}

if (Test-Path -LiteralPath (Join-Path $root '.git')) {
  $currentBranch = (& git -C $root branch --show-current 2>$null).Trim()
  if ($currentBranch -like 'feature/wsl-core*') {
    $base = 'e72a1abe573bb0e41eea410b235cb78da53e8a26'
    $changed = @(& git -C $root diff --name-only "$base...HEAD" 2>$null)
    $browserChanges = @($changed | Where-Object { $_ -match '(^|/)(Browser|browser)(/|\.|$)' })
    Require ($browserChanges.Count -eq 0) ('Browser files changed in secure Terminal branch: ' + ($browserChanges -join ', '))
    $databaseChanges = @($changed | Where-Object { $_ -match '(^|/)(database|db)(/|\.|$)' })
    Require ($databaseChanges.Count -eq 0) ('Database files changed in secure Terminal branch: ' + ($databaseChanges -join ', '))
  }
}

if ($failures.Count -gt 0) {
  $failures | ForEach-Object { Write-Error $_ }
  exit 1
}
Write-Host 'PASS CloudOS WSL core secure Terminal safety contract'
