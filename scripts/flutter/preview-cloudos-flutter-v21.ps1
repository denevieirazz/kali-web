[CmdletBinding()]
param(
    [switch]$Run,
    [switch]$SkipBuild,
    [switch]$SkipTests
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$uiRoot = Join-Path $repoRoot 'desktop\CloudOS.FlutterShell'
$nativeBridgeRoot = Join-Path $uiRoot 'native_bridge'
$releaseDir = Join-Path $uiRoot 'build\windows\x64\runner\Release'
$brokerBinDir = Join-Path $repoRoot 'desktop\CloudOS.NativeShell\bin\Release'
$brokerProject = Join-Path $repoRoot 'desktop\CloudOS.SystemBroker\CloudOS.SystemBroker.vcxproj'
$probeProject = Join-Path $repoRoot 'desktop\CloudOS.BrokerProbe\CloudOS.BrokerProbe.vcxproj'
$packageLauncher = Join-Path $repoRoot 'Abrir CloudOS V21 Flutter com System Broker.cmd'

function Assert-LastExitCode {
    param([Parameter(Mandatory = $true)][string]$Step)
    if ($LASTEXITCODE -ne 0) {
        throw "$Step falhou com codigo $LASTEXITCODE."
    }
}

Write-Host '[CloudOS V21] Preparando Flutter Shell + System Broker...' -ForegroundColor Cyan

if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    throw 'Flutter nao foi encontrado no PATH. Instale Flutter 3.44.7 e habilite Windows desktop.'
}

$versionOutput = (& flutter --version 2>&1 | Out-String)
Assert-LastExitCode 'flutter --version'
Write-Host '[CloudOS V21] Flutter detectado:' -ForegroundColor Cyan
Write-Host $versionOutput.Trim()

$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
if (-not (Test-Path $vswhere)) {
    throw 'Visual Studio Build Tools nao encontrado. Instale Desktop development with C++ e Windows SDK.'
}

$vsroot = (& $vswhere -latest -products * -requires Microsoft.Component.MSBuild -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath | Select-Object -First 1)
if ([string]::IsNullOrWhiteSpace($vsroot)) {
    throw 'MSBuild/VC++ x64 nao encontrado pelo vswhere.'
}
$vsroot = $vsroot.Trim()
$msbuild = Join-Path $vsroot 'MSBuild\Current\Bin\MSBuild.exe'
if (-not (Test-Path $msbuild)) {
    throw "MSBuild nao encontrado em $msbuild"
}

Write-Host '[CloudOS V21] Compilando System Broker...' -ForegroundColor Cyan
& $msbuild $brokerProject '/m' '/nologo' '/v:minimal' '/p:Configuration=Release' '/p:Platform=x64' | Out-Host
Assert-LastExitCode 'Build CloudOS.SystemBroker'

Write-Host '[CloudOS V21] Compilando Broker Probe...' -ForegroundColor Cyan
& $msbuild $probeProject '/m' '/nologo' '/v:minimal' '/p:Configuration=Release' '/p:Platform=x64' | Out-Host
Assert-LastExitCode 'Build CloudOS.BrokerProbe'

if (-not $SkipTests) {
    Write-Host '[CloudOS V21] Validando contrato do System Broker...' -ForegroundColor Cyan
    & pwsh -NoProfile -File (Join-Path $repoRoot 'scripts\native\test-system-broker-v21-contract.ps1') | Out-Host
    Assert-LastExitCode 'Contrato V21'

    Write-Host '[CloudOS V21] Executando smoke IPC do System Broker...' -ForegroundColor Cyan
    & pwsh -NoProfile -File (Join-Path $repoRoot 'scripts\native\run-system-broker-smoke-v21.ps1') | Out-Host
    Assert-LastExitCode 'Smoke V21'
}

Push-Location $uiRoot
try {
    Write-Host '[CloudOS V21] Habilitando Flutter Windows desktop...' -ForegroundColor Cyan
    & flutter config --enable-windows-desktop | Out-Host
    Assert-LastExitCode 'flutter config'

    if (-not (Test-Path (Join-Path $uiRoot 'windows\CMakeLists.txt'))) {
        Write-Host '[CloudOS V21] Gerando host Windows local...' -ForegroundColor Cyan
        & flutter create --platforms=windows --project-name cloudos_flutter_shell . | Out-Host
        Assert-LastExitCode 'flutter create'
    }

    $runnerDir = Join-Path $uiRoot 'windows\runner'
    if (-not (Test-Path $runnerDir)) {
        throw "Runner Windows nao encontrado em $runnerDir"
    }

    Write-Host '[CloudOS V21] Aplicando Native Bridge V21 ao runner...' -ForegroundColor Cyan
    Copy-Item -Path (Join-Path $nativeBridgeRoot '*') -Destination $runnerDir -Force

    $cmakePath = Join-Path $runnerDir 'CMakeLists.txt'
    if (-not (Test-Path $cmakePath)) {
        throw "CMakeLists do runner nao encontrado em $cmakePath"
    }

    $cmake = Get-Content -Path $cmakePath -Raw

    if ($cmake -notmatch 'cloudos_flutter_bridge_v20\.cpp') {
        $cmake = $cmake -replace '("flutter_window\.cpp")', "`$1`r`n  `"cloudos_flutter_bridge_v20.cpp`""
    }

    if ($cmake -notmatch 'cloudos_broker_client_v21\.cpp') {
        if ($cmake -match 'cloudos_flutter_bridge_v20\.cpp') {
            $cmake = $cmake -replace '("cloudos_flutter_bridge_v20\.cpp")', "`$1`r`n  `"cloudos_broker_client_v21.cpp`""
        }
        else {
            $cmake = $cmake -replace '("flutter_window\.cpp")', "`$1`r`n  `"cloudos_broker_client_v21.cpp`""
        }
    }

    if ($cmake -notmatch 'advapi32\.lib') {
        $cmake = $cmake -replace 'target_link_libraries\(\$\{BINARY_NAME\} PRIVATE flutter flutter_wrapper_app\)', 'target_link_libraries(${BINARY_NAME} PRIVATE flutter flutter_wrapper_app dwmapi.lib shlwapi.lib shell32.lib ole32.lib uuid.lib advapi32.lib)'
    }

    Set-Content -Path $cmakePath -Value $cmake -Encoding UTF8

    $templateTest = Join-Path $uiRoot 'test\widget_test.dart'
    if (Test-Path $templateTest) {
        Remove-Item $templateTest -Force
    }

    Write-Host '[CloudOS V21] Resolvendo dependencias...' -ForegroundColor Cyan
    & flutter pub get | Out-Host
    Assert-LastExitCode 'flutter pub get'

    Write-Host '[CloudOS V21] Analyzer...' -ForegroundColor Cyan
    & flutter analyze --fatal-infos --fatal-warnings | Out-Host
    Assert-LastExitCode 'flutter analyze'

    if (-not $SkipTests) {
        Write-Host '[CloudOS V21] Widget tests...' -ForegroundColor Cyan
        & flutter test | Out-Host
        Assert-LastExitCode 'flutter test'
    }

    if (-not $SkipBuild) {
        Write-Host '[CloudOS V21] Build Windows Release...' -ForegroundColor Cyan
        & flutter build windows --release | Out-Host
        Assert-LastExitCode 'flutter build windows'
    }
}
finally {
    Pop-Location
}

$shellExe = Join-Path $releaseDir 'cloudos_flutter_shell.exe'
$brokerExe = Join-Path $brokerBinDir 'CloudOS.SystemBroker.exe'
$probeExe = Join-Path $brokerBinDir 'CloudOS.BrokerProbe.exe'

if (-not (Test-Path $shellExe)) {
    if ($SkipBuild) {
        throw "-SkipBuild foi usado, mas o executavel Release nao existe em $shellExe"
    }
    throw "Flutter Release nao encontrado em $shellExe"
}
if (-not (Test-Path $brokerExe)) {
    throw "CloudOS.SystemBroker.exe nao encontrado em $brokerExe"
}
if (-not (Test-Path $probeExe)) {
    throw "CloudOS.BrokerProbe.exe nao encontrado em $probeExe"
}

Write-Host '[CloudOS V21] Montando pasta executavel...' -ForegroundColor Cyan
Copy-Item -Path $brokerExe -Destination $releaseDir -Force
Copy-Item -Path $probeExe -Destination $releaseDir -Force
if (Test-Path $packageLauncher) {
    Copy-Item -Path $packageLauncher -Destination (Join-Path $releaseDir 'Abrir CloudOS V21.cmd') -Force
}

Write-Host '[PASS] CloudOS V21 pronto para uso em:' -ForegroundColor Green
Write-Host $releaseDir -ForegroundColor Green

if ($Run) {
    Write-Host '[CloudOS V21] Abrindo Release. Winlogon/Explorer nao serao alterados.' -ForegroundColor Green
    Start-Process -FilePath $shellExe -WorkingDirectory $releaseDir
}
