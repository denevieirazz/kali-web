$ErrorActionPreference = 'Stop'
$base = '2d3380ba562d23e05947f81cc9581e8fe9bcfdbc'

if (-not (git cat-file -e "$base^{commit}" 2>$null)) { throw "Base oficial $base não disponível no checkout." }

$changed = @(git diff --name-only "$base...HEAD")
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
  'core/wsl/cloudos-core/internal/files/files.go'
)
foreach ($file in $required) {
  if (-not (Test-Path $file)) { throw "Arquivo obrigatório ausente: $file" }
}

$allFiles = @(
  './backend/src/files/routes.js',
  './backend/src/files/wslFilesRpcSession.js',
  './backend/src/files/wslFilesService.js',
  './backend/src/files/wslFileTransactions.js',
  './frontend/src/apps/CloudOSFiles/fileSourcePolicy.ts',
  './frontend/src/apps/CloudOSFiles/windowsDirectorySource.ts',
  './frontend/src/apps/CloudOSFiles/wslFileSource.ts'
)
$text = ($allFiles | ForEach-Object { Get-Content $_ -Raw }) -join "`n"

foreach ($token in @('--install','--import','--update','--terminate','--shutdown','--set-default','--set-version','-Verb RunAs')) {
  if ($text -match [regex]::Escape($token)) { throw "Mutação WSL/elevação proibida encontrada: $token" }
}

$routes = Get-Content './backend/src/files/routes.js' -Raw
if ($routes -notmatch 'x-cloudos-file-actor' -or $routes -notmatch "!== 'user-ui'") { throw 'Actor user-ui não está fixado na API real.' }
if ($routes -notmatch 'confirmed !== true') { throw 'Confirmação explícita de mutação ausente.' }

$policy = Get-Content './frontend/src/apps/CloudOSFiles/fileSourcePolicy.ts' -Raw
if ($policy -notmatch "value === '\.\.'" -or $policy -notmatch "value\.includes\('\\\\'\)") { throw 'Normalização de path frontend incompleta.' }

$linux = Get-Content './core/wsl/cloudos-core/internal/files/files.go' -Raw
if ($linux -notmatch 'O_NOFOLLOW' -or $linux -notmatch 'Openat' -or $linux -notmatch 'Renameat') { throw 'Filesystem Linux não usa resolução relativa/no-follow esperada.' }

Write-Output 'FILES_REAL_TRANSACTIONAL_CONTRACT_OK'
