$ErrorActionPreference='Stop'
$base='2d3380ba562d23e05947f81cc9581e8fe9bcfdbc'
$changed=@(git diff --name-only "$base...HEAD")
if($LASTEXITCODE -ne 0){throw 'DIFF_UNAVAILABLE'}
$forbidden=@(
  '^desktop/CloudOS\.Browser','^frontend/src/apps/Browser/','^tests/playwright/native-browser','^scripts/.*browser',
  '^backend/src/database/','^frontend/src/core/fs/(?!apps)','^core/wsl/cloudos-core/internal/protocol/','^backend/src/terminal/wslCoreAdapter\.js$',
  '^core/wsl/cloudos-core/internal/process/manager\.go$','^backend/src/wsl/'
)
foreach($path in $changed){foreach($pattern in $forbidden){if($path -match $pattern){throw "FORBIDDEN_CHANGE:$path"}}}
$allowed='^(?:\.github/workflows/linux-system-center-cgroups\.yml|docs/LINUX_SYSTEM_CENTER_CGROUPS\.md|core/wsl/cloudos-core/(?:cmd/cloudos-core/main\.go|internal/server/(?:server|systemcenter|systemcenter_test)\.go|internal/linuxproc/.+|internal/cgroups/.+)|backend/src/system/(?:routes|linuxSystemCenterService|wslCoreRpcSession)\.js|backend/test/linux-system-center-backend\.test\.js|frontend/src/apps/TaskManager/(?:TaskManager\.tsx|LinuxSystemCenter\.css|linuxSystemCenterClient\.ts|linuxSystemCenterModel\.(?:js|d\.ts))|frontend/test/(?:linuxSystemCenterModel|systemCenterComponentContract|systemCenterContract)\.test\.js|scripts/(?:probe-linux-system-center-cgroups\.mjs|probe-cgroup-control\.mjs|validate-linux-system-center-cgroups\.ps1|test-linux-system-center-cgroups-contract\.ps1))$'
foreach($path in $changed){if($path -notmatch $allowed){throw "UNEXPECTED_CHANGE:$path"}}

$rpc=Get-Content './backend/src/system/wslCoreRpcSession.js' -Raw
if($rpc -notmatch 'SecureFrameCodec' -or $rpc -notmatch 'deriveChannelMaterial' -or $rpc -match 'createCipheriv|createDecipheriv'){throw 'SECURE_CODEC_NOT_REUSED'}
if($rpc -notmatch 'shell:false'){throw 'SHELL_ENABLED'}
$routes=Get-Content './backend/src/system/routes.js' -Raw
if($routes -notmatch 'authenticateToken, requireAdmin' -or $routes -notmatch 'confirmed !== true'){throw 'DESTRUCTIVE_AUTH_CONTRACT_MISSING'}
if($routes -notmatch "\['SIGINT','SIGTERM','SIGKILL'\]"){throw 'SIGNAL_ALLOWLIST_CHANGED'}
$cgroup=Get-Content './core/wsl/cloudos-core/internal/cgroups/cgroups.go' -Raw
if($cgroup -match 'WriteFile\([^\r\n]*cgroup\.subtree_control'){throw 'CGROUP_DELEGATION_MUTATION_FORBIDDEN'}
if($cgroup -notmatch 'root-cgroup-write-forbidden' -or $cgroup -notmatch 'feature-flag-disabled'){throw 'CGROUP_FAIL_CLOSED_MISSING'}
$combined=(Get-Content './core/wsl/cloudos-core/internal/linuxproc/linuxproc.go' -Raw)+(Get-Content './core/wsl/cloudos-core/internal/cgroups/cgroups.go' -Raw)+(Get-Content './backend/src/system/wslCoreRpcSession.js' -Raw)+(Get-Content './scripts/validate-linux-system-center-cgroups.ps1' -Raw)+(Get-Content './scripts/probe-cgroup-control.mjs' -Raw)
if($combined -match '(?i)\bnmap\b|\bsqlmap\b|\bmetasploit\b|\bmsfvenom\b'){throw 'OFFENSIVE_TOOL_REFERENCE_FORBIDDEN'}
if($combined -match '(?i)\bsudo\b|/etc/wsl\.conf|--install|--update|--terminate|--shutdown|--set-version|--set-default|Start-Process\s+.*-Verb\s+RunAs'){throw 'WSL_OR_ELEVATION_MUTATION_FORBIDDEN'}
git diff --quiet "$base...HEAD" -- 'backend/src/terminal/wslCoreAdapter.js'; if($LASTEXITCODE -ne 0){throw 'TERMINAL_ADAPTER_CHANGED'}
git diff --quiet "$base...HEAD" -- 'core/wsl/cloudos-core/internal/protocol'; if($LASTEXITCODE -ne 0){throw 'CRYPTO_PROTOCOL_CHANGED'}
git diff --quiet "$base...HEAD" -- 'core/wsl/cloudos-core/internal/process/manager.go'; if($LASTEXITCODE -ne 0){throw 'GENERIC_ALLOWLIST_CHANGED'}
Write-Host 'PASS Linux System Center + cgroups safety contract'