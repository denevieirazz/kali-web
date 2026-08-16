$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$failures=[Collections.Generic.List[string]]::new()
function Require([bool]$ok,[string]$message){if(-not $ok){$script:failures.Add($message)}}

$session=Get-Content -LiteralPath (Join-Path $root 'frontend\src\apps\CloudOSTerminal\TerminalSession.tsx') -Raw
$transport=Get-Content -LiteralPath (Join-Path $root 'frontend\src\apps\CloudOSTerminal\terminalSessionTransport.js') -Raw
$socket=Get-Content -LiteralPath (Join-Path $root 'backend\src\terminal\websocket.js') -Raw
$physical=Get-Content -LiteralPath (Join-Path $root 'scripts\probe-visible-terminal-wsl-core.mjs') -Raw
$validator=Get-Content -LiteralPath (Join-Path $root 'scripts\validate-visible-terminal-wsl-core.ps1') -Raw
$dev=Get-Content -LiteralPath (Join-Path $root 'scripts\start-cloudos-visible-terminal-v2.ps1') -Raw

foreach($token in @('createTerminalTransport','data-backend-mode','Linux:','Transporte:','Estado:','transport.dispose()','terminal.dispose()','resizeObserver.disconnect()')){Require ($session.Contains($token)) "TerminalSession missing: $token"}
foreach($token in @('wsl-core-v2','aes-256-gcm-seq','legacy-fallback',"type: 'signal', signal: 'interrupt'","type: 'close'",'sanitizeTerminalError')){Require ($transport.Contains($token)) "transport missing: $token"}
Require ($transport -notmatch 'data\s*\+\s*["'']\\[rn]') 'Transport appends Enter/newline to user input.'
Require ($session -notmatch '(?i)(corePid|terminalPid|bootstrapDiagnostic|secret|nonce)') 'Visible Terminal exposes internal diagnostics or secrets.'

foreach($token in @("backendMode = 'wsl-core-v2'","backendMode = 'legacy-pty'",'wslCoreTerminalFallbackEnabled','verifySessionToken','await activeCore.close()')){Require ($socket.Contains($token)) "backend websocket contract missing: $token"}
foreach($flag in @('CLOUDOS_WSL_CORE_FOUNDATION','CLOUDOS_WSL_CORE_TERMINAL','CLOUDOS_WSL_CORE_LINUX_PATH','CLOUDOS_WSL_CORE_TERMINAL_FALLBACK')){Require ($dev.Contains($flag)) "dev launcher missing flag $flag";Require ($validator.Contains($flag)) "physical validator missing flag $flag"}
Require ($validator -match "CLOUDOS_WSL_CORE_TERMINAL_FALLBACK='0'") 'Physical validator must be fail-closed.'
foreach($command in @('uname -a','pwd','id','sleep 30','sleep 60')){Require ($physical.Contains($command)) "Physical probe missing benign command: $command"}
Require ($physical -notmatch '(?i)(nmap|sqlmap|metasploit|msfvenom|nikto|gobuster)') 'Physical probe references offensive tooling.'

$base='7424eb7c8775bb534f05ff0c7efedbc55a50e551'
if(Test-Path -LiteralPath (Join-Path $root '.git')){
  $changed=@(& git -C $root diff --name-only "$base...HEAD")
  $forbidden=@($changed|Where-Object{$_ -match '(^|/)(Browser|SystemCenter|ProcessManager|KaliToolCenter)(/|\.|$)' -or $_ -match '^core/wsl/cloudos-core/' -or $_ -match '^desktop/CloudOS\.WslCore' -or $_ -eq 'backend/src/terminal/wslCoreAdapter.js' -or $_ -match '(^|/)(database|db)(/|\.|$)'})
  Require ($forbidden.Count -eq 0) ('Forbidden validated/excluded files changed: '+($forbidden -join ', '))
}
foreach($textAndName in @(@($validator,'validator'),@($dev,'dev launcher'))){
  foreach($forbidden in @('--install','--import','--update','--terminate','--shutdown','--set-default','--set-version','-Verb RunAs')){
    Require ($textAndName[0].IndexOf($forbidden,[StringComparison]::OrdinalIgnoreCase) -lt 0) "$($textAndName[1]) contains forbidden WSL mutation/elevation token: $forbidden"
  }
}
if($failures.Count){$failures|ForEach-Object{Write-Error $_};exit 1}
Write-Host 'PASS visible Terminal -> WSL Core v2 contract'
