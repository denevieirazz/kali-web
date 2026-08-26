[CmdletBinding()]
param(
    [ValidatePattern('^[a-fA-F0-9]{40}$')]
    [string] $ExpectedHeadSha,

    [switch] $Remove
)

$ErrorActionPreference = 'Stop'
$repoRoot = [System.IO.Path]::GetFullPath((Get-Location).Path)
$projectPath = Join-Path $repoRoot 'desktop\CloudOS.Host.Tests\CloudOS.Host.Tests.csproj'
$fixtureExe = Join-Path $repoRoot 'desktop\CloudOS.Host.Tests\bin\Release\net8.0\CloudOS.Host.Tests.exe'
$fixtureRoot = Join-Path $env:LOCALAPPDATA 'CloudOS\PhysicalProof\WindowsContainedRuntime'
$scriptPath = Join-Path $fixtureRoot 'cloudos-contained-gui-fixture.cmd'
$manifestPath = Join-Path $fixtureRoot 'fixture-manifest.json'
$startMenuDirectory = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\CloudOS Physical Proof'
$shortcutPath = Join-Path $startMenuDirectory 'CloudOS BAT Contained Fixture.lnk'

function Remove-IfEmpty {
    param([Parameter(Mandatory)] [string] $Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) { return }
    if (@(Get-ChildItem -LiteralPath $Path -Force).Count -eq 0) {
        Remove-Item -LiteralPath $Path -Force
    }
}

function Remove-Fixture {
    if (Test-Path -LiteralPath $shortcutPath -PathType Leaf) {
        Remove-Item -LiteralPath $shortcutPath -Force
    }
    Remove-IfEmpty -Path $startMenuDirectory

    if (Test-Path -LiteralPath $scriptPath -PathType Leaf) {
        Remove-Item -LiteralPath $scriptPath -Force
    }
    if (Test-Path -LiteralPath $manifestPath -PathType Leaf) {
        Remove-Item -LiteralPath $manifestPath -Force
    }
    Remove-IfEmpty -Path $fixtureRoot

    Write-Host 'CloudOS Windows contained-runtime physical fixture removida.' -ForegroundColor Green
    Write-Host "Shortcut: $shortcutPath"
    Write-Host "Script:   $scriptPath"
}

if ($Remove) {
    Remove-Fixture
    return
}

if ([string]::IsNullOrWhiteSpace($ExpectedHeadSha)) {
    throw 'ExpectedHeadSha é obrigatório ao preparar a fixture.'
}
if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA) -or [string]::IsNullOrWhiteSpace($env:APPDATA)) {
    throw 'LOCALAPPDATA/APPDATA não estão disponíveis nesta sessão Windows.'
}
if (@(Get-Process -Name 'CloudOS.Host' -ErrorAction SilentlyContinue).Count -gt 0) {
    throw 'Feche o CloudOS.Host antes de preparar a fixture para evitar catálogo Windows em cache.'
}
if (-not (Test-Path -LiteralPath $projectPath -PathType Leaf)) {
    throw "Projeto de fixture não encontrado: $projectPath"
}

$headOutput = @(git rev-parse HEAD)
if ($LASTEXITCODE -ne 0 -or $headOutput.Count -ne 1) {
    throw 'Não foi possível determinar o HEAD atual do Git.'
}
$currentHead = ([string]$headOutput[0]).Trim().ToLowerInvariant()
if ($currentHead -notmatch '^[a-f0-9]{40}$') {
    throw "HEAD Git inválido: $currentHead"
}
if ($currentHead -ne $ExpectedHeadSha.ToLowerInvariant()) {
    throw "HEAD incorreto para a fixture física. esperado=$ExpectedHeadSha atual=$currentHead"
}

Write-Host 'Compilando a fixture Win32 já existente em CloudOS.Host.Tests...'
& dotnet build $projectPath -c Release --nologo
if ($LASTEXITCODE -ne 0) {
    throw "dotnet build falhou com exit code $LASTEXITCODE."
}
if (-not (Test-Path -LiteralPath $fixtureExe -PathType Leaf)) {
    throw "Executável da fixture não foi produzido: $fixtureExe"
}
if ($fixtureExe -match '[%\r\n\0]' -or $scriptPath -match '[%\r\n\0]') {
    throw 'O caminho físico contém caracteres incompatíveis com o contrato windows-script-direct.'
}

[System.IO.Directory]::CreateDirectory($fixtureRoot) | Out-Null
[System.IO.Directory]::CreateDirectory($startMenuDirectory) | Out-Null

$escapedExe = $fixtureExe.Replace('"', '""')
$scriptContent = @(
    '@echo off',
    'setlocal',
    "\"$escapedExe\" --native-contained-fixture-window",
    'exit /b %ERRORLEVEL%'
) -join "`r`n"
$scriptContent += "`r`n"
$ascii = [System.Text.Encoding]::ASCII
[System.IO.File]::WriteAllText($scriptPath, $scriptContent, $ascii)

$shell = $null
$shortcut = $null
try {
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($shortcutPath)
    $shortcut.TargetPath = $scriptPath
    $shortcut.WorkingDirectory = $fixtureRoot
    $shortcut.Description = 'CloudOS contained-runtime physical BAT GUI descendant fixture'
    $shortcut.Save()
}
finally {
    if ($null -ne $shortcut) { [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($shortcut) }
    if ($null -ne $shell) { [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($shell) }
}

if (-not (Test-Path -LiteralPath $shortcutPath -PathType Leaf)) {
    throw "Atalho da fixture não foi criado: $shortcutPath"
}

$verifyShell = $null
$verifyShortcut = $null
try {
    $verifyShell = New-Object -ComObject WScript.Shell
    $verifyShortcut = $verifyShell.CreateShortcut($shortcutPath)
    $resolvedTarget = [System.IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables([string]$verifyShortcut.TargetPath))
    if ($resolvedTarget -ne [System.IO.Path]::GetFullPath($scriptPath)) {
        throw "O atalho não aponta para a fixture esperada. atual=$resolvedTarget esperado=$scriptPath"
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$verifyShortcut.Arguments)) {
        throw 'O atalho físico contém argumentos crus; a fixture deve usar windows-script-direct sem argumentos de atalho.'
    }
}
finally {
    if ($null -ne $verifyShortcut) { [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($verifyShortcut) }
    if ($null -ne $verifyShell) { [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($verifyShell) }
}

$manifest = [ordered]@{
    SchemaVersion = 1
    PreparedAt = [DateTimeOffset]::UtcNow.ToString('o')
    GitHeadSha = $currentHead
    FixtureName = 'CloudOS BAT Contained Fixture'
    ShortcutPath = $shortcutPath
    ScriptPath = $scriptPath
    ScriptSha256 = (Get-FileHash -LiteralPath $scriptPath -Algorithm SHA256).Hash.ToLowerInvariant()
    FixtureExecutable = $fixtureExe
    FixtureExecutableSha256 = (Get-FileHash -LiteralPath $fixtureExe -Algorithm SHA256).Hash.ToLowerInvariant()
    FixtureArgument = '--native-contained-fixture-window'
    ExpectedCatalogKind = 'windows-script-direct'
    ExpectedCommandProcessor = Join-Path $env:SystemRoot 'System32\cmd.exe'
    CleanupCommand = 'pwsh -NoProfile -File scripts/prepare-windows-contained-runtime-physical-fixture.ps1 -Remove'
}
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
[System.IO.File]::WriteAllText(
    $manifestPath,
    (($manifest | ConvertTo-Json -Depth 8) + [Environment]::NewLine),
    $utf8NoBom)

Write-Host ''
Write-Host 'CloudOS Windows contained-runtime physical fixture: READY' -ForegroundColor Green
Write-Host "Git HEAD:  $currentHead"
Write-Host "Menu name: CloudOS BAT Contained Fixture"
Write-Host "Shortcut:  $shortcutPath"
Write-Host "Script:    $scriptPath"
Write-Host "Manifest:  $manifestPath"
Write-Host ''
Write-Host 'Agora inicie o CloudOS em modo Full. O catálogo será criado já com a fixture presente.'
Write-Host 'Depois execute run-windows-contained-runtime-physical-proof.ps1 e abra “CloudOS BAT Contained Fixture” quando solicitado.'
