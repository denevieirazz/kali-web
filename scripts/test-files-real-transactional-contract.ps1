$ErrorActionPreference = 'Stop'
$base = '2d3380ba562d23e05947f81cc9581e8fe9bcfdbc'

& git rev-parse --verify "$($base)^{commit}" *> $null
if ($LASTEXITCODE -ne 0) { throw "Base oficial $base não disponível no checkout." }

$changed = @(git diff --name-only "$base...HEAD")
if ($LASTEXITCODE -ne 0) { throw "Não foi possível comparar HEAD com a base oficial $base." }
if (-not $changed.Count) { throw 'Nenhuma mudança detectada para Files real/transacional.' }

$forbiddenPatterns = @(
  '^frontend/src/apps/Browser',
  '^desktop/CloudOS\.Browser',
  '^frontend/src/apps/TaskManager/',
  '^backend/src/system/',
  '^backend/src/(db|database)/',
  '^frontend/src/apps/CloudOSTerminal/',
  '^backend/src/terminal/wslCoreAdapter\.js$',
  '^core/wsl/cloudos-core/internal/protocol/'
)

foreach ($file in $changed) {
  foreach ($pattern in $forbiddenPatterns) {
    if ($file -match $pattern) { throw "Fronteira violada: $file" }
  }
}

$required = @(
  'frontend/src/apps/CloudOSFiles/CloudOSFiles.tsx',
  'frontend/src/apps/CloudOSFiles/windowsDirectorySource.ts',
  'frontend/src/apps/CloudOSFiles/wslFileSource.ts',
  'backend/src/files/routes.js',
  'backend/src/files/wslFilesRpcSession.js',
  'core/wsl/cloudos-core/internal/files/files.go',
  'scripts/start-cloudos-files-real-transactional.ps1'
)
foreach ($file in $required) {
  if (-not (Test-Path $file)) { throw "Arquivo obrigatório ausente: $file" }
}

$scanFiles = @(
  './backend/src/files/routes.js',
  './backend/src/files/wslFilesRpcSession.js',
  './backend/src/files/wslFilesService.js',
  './backend/src/files/wslFileTransactions.js',
  './frontend/src/apps/CloudOSFiles/fileSourcePolicy.ts',
  './frontend/src/apps/CloudOSFiles/windowsDirectorySource.ts',
  './frontend/src/apps/CloudOSFiles/wslFileSource.ts',
  './scripts/start-cloudos-files-real-transactional.ps1'
)
$text = ($scanFiles | ForEach-Object { Get-Content $_ -Raw }) -join "`n"

foreach ($token in @('--install','--import','--update','--terminate','--set-default','--set-version','-Verb RunAs')) {
  if ($text.Contains($token, [System.StringComparison]::OrdinalIgnoreCase)) { throw "Mutação WSL/elevação proibida encontrada: $token" }
}

$routes = Get-Content './backend/src/files/routes.js' -Raw
foreach ($requiredText in @('x-cloudos-file-actor', "!== 'user-ui'", 'confirmed !== true', 'authenticateToken')) {
  if (-not $routes.Contains($requiredText, [System.StringComparison]::Ordinal)) { throw "Contrato de autorização ausente: $requiredText" }
}

$policy = Get-Content './frontend/src/apps/CloudOSFiles/fileSourcePolicy.ts' -Raw
foreach ($requiredText in @("value === '..'", "value.includes('/')", "value.includes('\\')", 'TextEncoder')) {
  if (-not $policy.Contains($requiredText, [System.StringComparison]::Ordinal)) { throw "Normalização de path frontend incompleta: $requiredText" }
}

$linux = Get-Content './core/wsl/cloudos-core/internal/files/files.go' -Raw
foreach ($requiredText in @('O_NOFOLLOW', 'Openat', 'Renameat', 'Fchmod', '.cloudos-trash')) {
  if (-not $linux.Contains($requiredText, [System.StringComparison]::Ordinal)) { throw "Contrato Linux ausente: $requiredText" }
}

$rpc = Get-Content './backend/src/files/wslFilesRpcSession.js' -Raw
foreach ($requiredText in @('SecureFrameCodec', 'deriveChannelMaterial', 'shell: false', 'CLOUDOS_WSL_CORE_FILES')) {
  if (-not $rpc.Contains($requiredText, [System.StringComparison]::Ordinal)) { throw "Contrato WSL Core v2 ausente: $requiredText" }
}
if ($rpc.Contains('createCipheriv', [System.StringComparison]::Ordinal) -or $rpc.Contains('createDecipheriv', [System.StringComparison]::Ordinal)) {
  throw 'Files reimplementou crypto em vez de reutilizar o codec aprovado.'
}

$launcher = Get-Content './scripts/start-cloudos-files-real-transactional.ps1' -Raw
foreach ($requiredText in @("CLOUDOS_WSL_CORE_FOUNDATION='1'", "CLOUDOS_WSL_CORE_FILES='1'", 'DATABASE_PATH=(Join-Path $data', 'Remove-CloudOSTemporaryCore', 'Stop-CloudOSOwnedProcess')) {
  if (-not $launcher.Contains($requiredText, [System.StringComparison]::Ordinal)) { throw "Launcher físico não mantém isolamento esperado: $requiredText" }
}

Write-Output 'FILES_REAL_TRANSACTIONAL_CONTRACT_OK'
