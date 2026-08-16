$ErrorActionPreference = 'Stop'
$base = '2d3380ba562d23e05947f81cc9581e8fe9bcfdbc'

& git rev-parse --verify "$($base)^{commit}" *> $null
if ($LASTEXITCODE -ne 0) { throw "Base oficial $base não disponível no checkout." }

$changed = @(git diff --name-only "$base...HEAD")
if ($LASTEXITCODE -ne 0) { throw 'Não foi possível comparar o lote com a base oficial.' }
if (-not $changed.Count) { throw 'Nenhuma mudança encontrada no lote.' }

$forbiddenPatterns = @(
  '^frontend/src/apps/Browser',
  '^desktop/CloudOS\.Browser',
  '^core/wsl/cloudos-core/',
  '^desktop/CloudOS\.WslCore/',
  '^frontend/src/apps/CloudOSTerminal/',
  '^backend/src/terminal/',
  '^frontend/src/apps/(TaskManager|SystemMonitor|SystemCenter)/',
  '^backend/src/system/',
  '^backend/src/database/',
  '^backend/src/db/',
  '/protocol/'
)
foreach ($file in $changed) {
  foreach ($pattern in $forbiddenPatterns) {
    if ($file -match $pattern) { throw "Fronteira proibida alterada: $file" }
  }
}

$security = Get-Content './backend/src/auth/security.js' -Raw
foreach ($required in @('password.length < 4','password.length > 128','crypto.randomBytes(22)','RECOVERY_RANDOM_BITS','hashRecoveryCode','verifyRecoveryCode')) {
  if (-not $security.Contains($required, [System.StringComparison]::Ordinal)) { throw "Contrato auth ausente: $required" }
}
if ($security.Contains("toString('base64url')", [System.StringComparison]::Ordinal) -or $security.Contains('toString("base64url")', [System.StringComparison]::Ordinal)) {
  throw 'Recovery code voltou a usar Base64 URL.'
}

$account = Get-Content './frontend/src/services/accountContract.js' -Raw
if (-not $account.Contains('MIN_PASSWORD_LENGTH = 4', [System.StringComparison]::Ordinal)) { throw 'Frontend não expõe mínimo de senha 4.' }

$setupCss = Get-Content './frontend/src/components/Setup/SetupWizard.css' -Raw
foreach ($required in @('overflow-x: hidden','scrollbar-gutter: stable','minmax(0, 1fr)','box-sizing: border-box','.setup-input:focus-visible')) {
  if (-not $setupCss.Contains($required, [System.StringComparison]::Ordinal)) { throw "Contrato responsivo ausente: $required" }
}

$recoveryActions = Get-Content './frontend/src/services/recoveryCodeActions.ts' -Raw
foreach ($required in @('showSaveFilePicker','navigator.clipboard.writeText','windowRef.print()')) {
  if (-not $recoveryActions.Contains($required, [System.StringComparison]::Ordinal)) { throw "Ação explícita de recovery ausente: $required" }
}
foreach ($forbidden in @('localStorage','indexedDB','navigator.storage.getDirectory','cloudos_files')) {
  if ($recoveryActions.Contains($forbidden, [System.StringComparison]::OrdinalIgnoreCase)) { throw "Persistência automática proibida encontrada: $forbidden" }
}

$thumbnail = Get-Content './frontend/src/apps/CloudOSFiles/thumbnailManager.js' -Raw
foreach ($required in @('MAX_THUMBNAIL_SOURCE_BYTES','THUMBNAIL_CONCURRENCY','signal?.aborted','URL.revokeObjectURL','thumbnailEligible(file, maxBytes)')) {
  if (-not $thumbnail.Contains($required, [System.StringComparison]::Ordinal)) { throw "Contrato de miniatura ausente: $required" }
}
foreach ($forbidden in @('.arrayBuffer(','file.text(')) {
  if ($thumbnail.Contains($forbidden, [System.StringComparison]::Ordinal)) { throw "Miniatura carrega conteúdo integral por API proibida: $forbidden" }
}

$filesUi = Get-Content './frontend/src/apps/CloudOSFiles/CloudOSFiles.tsx' -Raw
foreach ($required in @("PresentationMode = 'grid' | 'list'",'isSymlinkEntry(entry)','data-view-mode={presentationMode}')) {
  if (-not $filesUi.Contains($required, [System.StringComparison]::Ordinal)) { throw "Contrato visual Files ausente: $required" }
}

# Este lote parte da linha oficial e não importa a branch Files real/transacional ainda não promovida.
# Também não deve inventar transferência cross-provider neste lote.
foreach ($path in @(
  './frontend/src/apps/CloudOSFiles/windowsDirectorySource.ts',
  './frontend/src/apps/CloudOSFiles/wslFileSource.ts',
  './backend/src/files/wslFilesService.js'
)) {
  if (Test-Path -LiteralPath $path) { throw "Provider não-oficial/cross-provider entrou indevidamente no lote: $path" }
}

Write-Output 'ONBOARDING_FILES_UX_CONTRACT_OK'
