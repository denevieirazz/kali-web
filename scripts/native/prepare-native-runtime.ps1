[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $IsWindows) { throw 'CLOUDOS_NATIVE_RUNTIME_WINDOWS_REQUIRED' }

$buildScript = Join-Path $PSScriptRoot 'build-native-runtime.ps1'

try {
    & $buildScript -Configuration Release -Required
    Write-Host '[CloudOS.NativeRuntime] MSVC already available and runtime built.'
    exit 0
} catch {
    if ($_.Exception.Message -notmatch 'MSVC_BUILD_TOOLS_MISSING') { throw }
}

$winget = Get-Command winget.exe -ErrorAction SilentlyContinue
if (-not $winget) {
    throw 'WINGET_REQUIRED_TO_INSTALL_MSVC: install Visual Studio 2022 Build Tools with Desktop development with C++'
}

Write-Host '[CloudOS.NativeRuntime] Installing Visual Studio 2022 Build Tools C++ workload.'
Write-Host '[CloudOS.NativeRuntime] This is a large one-time developer dependency and may request elevation.'

$override = '--wait --passive --norestart --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended'
& $winget.Source install --id Microsoft.VisualStudio.2022.BuildTools --exact --source winget --accept-package-agreements --accept-source-agreements --override $override
if ($LASTEXITCODE -ne 0) { throw "MSVC_BUILD_TOOLS_INSTALL_FAILED:exit=$LASTEXITCODE" }

& $buildScript -Configuration Release -Required
Write-Host '[CloudOS.NativeRuntime] Native C++ toolchain ready.'
