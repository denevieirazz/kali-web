[CmdletBinding()]
param(
    [switch]$Run,
    [switch]$SkipBuild
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$uiRoot = Join-Path $repoRoot 'desktop\CloudOS.FlutterShell'

if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    throw 'Flutter nao foi encontrado no PATH. Instale Flutter 3.44.7 e habilite Windows desktop.'
}

$versionOutput = (& flutter --version 2>&1 | Out-String)
if ($LASTEXITCODE -ne 0) {
    throw "flutter --version falhou:`n$versionOutput"
}

Write-Host '[CloudOS Flutter V19] Flutter detectado:' -ForegroundColor Cyan
Write-Host $versionOutput.Trim()

Push-Location $uiRoot
try {
    & flutter config --enable-windows-desktop | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'flutter config falhou.' }

    if (-not (Test-Path (Join-Path $uiRoot 'windows\CMakeLists.txt'))) {
        Write-Host '[CloudOS Flutter V19] Gerando host Windows padrao local...' -ForegroundColor Cyan
        & flutter create --platforms=windows --project-name cloudos_flutter_shell . | Out-Host
        if ($LASTEXITCODE -ne 0) { throw 'flutter create falhou.' }
    }

    # flutter create injects the template MyApp widget test into an existing
    # package. V19 owns its deterministic shell_smoke_test instead.
    $templateTest = Join-Path $uiRoot 'test\widget_test.dart'
    if (Test-Path $templateTest) {
        Remove-Item $templateTest -Force
    }

    # Keep the generated runner synchronized with the tracked native bridge.
    # The host is intentionally generated locally and is not committed.
    Copy-Item -Path (Join-Path $uiRoot 'native_bridge\*') `
        -Destination (Join-Path $uiRoot 'windows\runner') -Force
    Copy-Item -LiteralPath (Join-Path $uiRoot '..\CloudOS.SystemBroker\src\protocol_v21.h') `
        -Destination (Join-Path $uiRoot 'windows\runner\protocol_v21.h') -Force
    Copy-Item -LiteralPath (Join-Path $uiRoot '..\CloudOS.SystemBroker\src\protocol_v21.cpp') `
        -Destination (Join-Path $uiRoot 'windows\runner\protocol_v21.cpp') -Force
    $stagedCommon = Join-Path $uiRoot 'CloudOS.NativeCommon'
    New-Item -ItemType Directory -Force -Path $stagedCommon | Out-Null
    foreach ($header in @(
        'native_shell_activation_v21.h',
        'native_shell_activation_client_v21.h',
        'native_shell_notification_v21.h',
        'native_shell_notification_client_v21.h'
    )) {
        Copy-Item -LiteralPath (Join-Path $uiRoot "..\CloudOS.NativeCommon\$header") `
            -Destination (Join-Path $stagedCommon $header) -Force
    }
    $runnerCmake = Join-Path $uiRoot 'windows\runner\CMakeLists.txt'
    $cmake = Get-Content -LiteralPath $runnerCmake -Raw
    if ($cmake -notmatch 'cloudos_flutter_bridge_v20\.cpp') {
        $cmake = $cmake -replace '(\s*"flutter_window\.cpp")', "`$1`n  `"cloudos_flutter_bridge_v20.cpp`"`n  `"cloudos_broker_client_v21.cpp`"`n  `"cloudos_conpty_manager.cpp`"`n  `"protocol_v21.cpp`""
        $cmake = $cmake -replace 'target_link_libraries\(\$\{BINARY_NAME\} PRIVATE flutter flutter_wrapper_app\)', 'target_link_libraries(${BINARY_NAME} PRIVATE flutter flutter_wrapper_app dwmapi.lib shlwapi.lib shell32.lib ole32.lib uuid.lib advapi32.lib)'
        Set-Content -LiteralPath $runnerCmake -Value $cmake -Encoding UTF8
    }
    elseif ($cmake -notmatch 'cloudos_conpty_manager\.cpp') {
        $cmake = $cmake -replace '(\s*"cloudos_broker_client_v21\.cpp")', "`$1`n  `"cloudos_conpty_manager.cpp`""
        Set-Content -LiteralPath $runnerCmake -Value $cmake -Encoding UTF8
    }

    Write-Host '[CloudOS Flutter V19] Resolvendo dependencias...' -ForegroundColor Cyan
    & flutter pub get | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'flutter pub get falhou.' }

    Write-Host '[CloudOS Flutter V19] Analyzer...' -ForegroundColor Cyan
    & flutter analyze --fatal-infos --fatal-warnings | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'flutter analyze falhou.' }

    Write-Host '[CloudOS Flutter V19] Widget tests...' -ForegroundColor Cyan
    & flutter test | Out-Host
    if ($LASTEXITCODE -ne 0) { throw 'flutter test falhou.' }

    if (-not $SkipBuild) {
        Write-Host '[CloudOS Flutter V19] Build Windows Release...' -ForegroundColor Cyan
        & flutter build windows --release | Out-Host
        if ($LASTEXITCODE -ne 0) { throw 'flutter build windows falhou.' }
    }

    if ($Run) {
        Write-Host '[CloudOS Flutter V19] Abrindo preview. Nenhum Winlogon/shell activation sera alterado.' -ForegroundColor Green
        & flutter run -d windows
        if ($LASTEXITCODE -ne 0) { throw 'flutter run falhou.' }
    }
    else {
        Write-Host '[CloudOS Flutter V19] PASS' -ForegroundColor Green
    }
}
finally {
    Pop-Location
}
