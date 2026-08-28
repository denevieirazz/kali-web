[CmdletBinding()]
param(
    [ValidateSet('Debug','Release')][string]$Configuration = 'Release',
    [string]$OutputDirectory = '',
    [switch]$Required
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$project = Join-Path $root 'desktop\CloudOS.NativeRuntime\CloudOS.NativeRuntime.vcxproj'

function Find-MSBuildWithVCTools {
    $direct = Get-Command msbuild.exe -ErrorAction SilentlyContinue
    if ($direct) { return $direct.Source }

    $vswhereCandidates = @(
        (Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'),
        (Join-Path $env:ProgramFiles 'Microsoft Visual Studio\Installer\vswhere.exe')
    ) | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Leaf) }

    foreach ($vswhere in $vswhereCandidates) {
        $found = @(& $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -find 'MSBuild\**\Bin\MSBuild.exe' 2>$null | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Leaf) })
        if ($found.Count -gt 0) { return [string]$found[0] }
    }
    return $null
}

function Normalize-CloudOSOutputDirectory {
    param([AllowEmptyString()][string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return '' }

    # MSBuild properties representing directories conventionally end in a backslash.
    # When such a value is interpolated inside a quoted Exec argument, Windows argv
    # parsing can preserve the closing quote as a literal character (C:\path\").
    # Accept that transport artifact here; never let it become part of a filesystem path.
    $candidate = $Path.Trim()
    while ($candidate.Length -gt 0 -and ($candidate[0] -eq '"' -or $candidate[0] -eq "'")) {
        $candidate = $candidate.Substring(1)
    }
    while ($candidate.Length -gt 0 -and ($candidate[$candidate.Length - 1] -eq '"' -or $candidate[$candidate.Length - 1] -eq "'")) {
        $candidate = $candidate.Substring(0, $candidate.Length - 1)
    }
    if ([string]::IsNullOrWhiteSpace($candidate)) { throw 'CLOUDOS_NATIVE_RUNTIME_OUTPUT_DIRECTORY_INVALID' }
    return [IO.Path]::GetFullPath($candidate)
}

if (-not $IsWindows) {
    if ($Required) { throw 'CLOUDOS_NATIVE_RUNTIME_WINDOWS_REQUIRED' }
    Write-Host '[CloudOS.NativeRuntime] skipped: Windows host required.'
    exit 0
}

$msbuild = Find-MSBuildWithVCTools
if (-not $msbuild) {
    $message = 'MSVC_BUILD_TOOLS_MISSING: run Preparar Runtime Nativo.cmd once'
    if ($Required) { throw $message }
    Write-Warning "[CloudOS.NativeRuntime] $message. Managed runtime fallback remains available."
    exit 0
}

Write-Host "[CloudOS.NativeRuntime] Building $Configuration with $msbuild"
& $msbuild $project '/t:Build' "/p:Configuration=$Configuration" '/p:Platform=x64' '/m' '/nologo' '/verbosity:minimal'
if ($LASTEXITCODE -ne 0) { throw "CLOUDOS_NATIVE_RUNTIME_BUILD_FAILED:exit=$LASTEXITCODE" }

$dll = Join-Path $root "desktop\CloudOS.NativeRuntime\bin\$Configuration\CloudOS.NativeRuntime.dll"
if (-not (Test-Path -LiteralPath $dll -PathType Leaf)) { throw "CLOUDOS_NATIVE_RUNTIME_OUTPUT_MISSING:$dll" }

$normalizedOutputDirectory = Normalize-CloudOSOutputDirectory $OutputDirectory
if (-not [string]::IsNullOrWhiteSpace($normalizedOutputDirectory)) {
    New-Item -ItemType Directory -Force -Path $normalizedOutputDirectory | Out-Null
    Copy-Item -LiteralPath $dll -Destination (Join-Path $normalizedOutputDirectory 'CloudOS.NativeRuntime.dll') -Force
}

Write-Host "CLOUDOS_NATIVE_RUNTIME_BUILT configuration=$Configuration dll=$dll"
