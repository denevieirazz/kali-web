[CmdletBinding()]
param(
    [string]$Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Read-RepoText {
    param([Parameter(Mandatory = $true)][string]$RelativePath)
    $path = Join-Path $Root $RelativePath
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "V15 required repository guide is missing: $RelativePath"
    }
    return Get-Content -LiteralPath $path -Raw
}

function Assert-Contains {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][string]$Needle,
        [Parameter(Mandatory = $true)][string]$Message
    )
    if (-not $Text.Contains($Needle)) { throw $Message }
}

function Assert-NotContains {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][string]$Needle,
        [Parameter(Mandatory = $true)][string]$Message
    )
    if ($Text.Contains($Needle)) { throw $Message }
}

$requiredGuides = @(
    '.editorconfig',
    'AGENTS.md',
    'README.md',
    'docs\ARCHITECTURE.md',
    'docs\native\README.md',
    'docs\native\ARCHITECTURE.md',
    'docs\native\CODEMAP.md',
    'docs\native\VALIDATION.md',
    'docs\native\DESKTOP_SYSTEM_ROADMAP.md',
    'desktop\CloudOS.NativeShell\src\README.md',
    'desktop\CloudOS.NativeRuntime\README.md',
    'desktop\CloudOS.NativeRecovery\README.md',
    'desktop\CloudOS.NativeCommon\README.md',
    'scripts\native\README.md'
)
foreach ($path in $requiredGuides) { [void](Read-RepoText -RelativePath $path) }

$rootReadme = Read-RepoText -RelativePath 'README.md'
Assert-Contains $rootReadme 'CloudOS Native Shell' 'Root README must identify the current native product.'
Assert-Contains $rootReadme 'AGENTS.md' 'Root README must route agents to AGENTS.md.'
Assert-Contains $rootReadme 'docs/native/CODEMAP.md' 'Root README must route readers to the native code map.'
Assert-NotContains $rootReadme 'CloudOS Unified é um shell desktop híbrido' 'Root README regressed to the obsolete hybrid desktop description.'

$agents = Read-RepoText -RelativePath 'AGENTS.md'
foreach ($needle in @(
    'desktop/CloudOS.NativeShell/src/main_shell_v2.cpp',
    'desktop/CloudOS.NativeRecovery/main.cpp',
    'CloudOS.Deployment.V13.psm1',
    'CloudOS.ShellActivation.V14.psm1',
    'test-native-contract-suite.ps1'
)) {
    Assert-Contains $agents $needle "AGENTS.md is missing native source-of-truth pointer: $needle"
}
Assert-Contains $agents 'configure-cloudos-shell-launcher.ps1' 'AGENTS.md must identify the legacy Shell Launcher path.'

$nativeArchitecture = Read-RepoText -RelativePath 'docs\native\ARCHITECTURE.md'
foreach ($needle in @('CloudOS.Supervisor.exe', 'CloudOS.exe --supervised', 'CloudOS.NativeRuntime.dll', 'V13', 'V14')) {
    Assert-Contains $nativeArchitecture $needle "Native architecture guide is missing: $needle"
}

$compatArchitecture = Read-RepoText -RelativePath 'docs\ARCHITECTURE.md'
Assert-Contains $compatArchitecture 'docs/native/ARCHITECTURE.md' 'Compatibility architecture document must point to the native authority.'
Assert-Contains $compatArchitecture 'compatibilidade' 'Compatibility architecture document must label its non-authoritative role.'
Assert-NotContains $compatArchitecture 'O fluxo padrão inicia `CloudOS.Host` diretamente' 'Compatibility architecture still claims CloudOS.Host is the current default desktop.'

$codeMap = Read-RepoText -RelativePath 'docs\native\CODEMAP.md'
foreach ($needle in @(
    'main_shell_v2.cpp',
    'CloudOS.NativeShell.vcxproj',
    'CloudOS.NativeRecovery/main.cpp',
    'CloudOS.Deployment.V13.psm1',
    'CloudOS.ShellActivation.V14.psm1'
)) {
    Assert-Contains $codeMap $needle "CODEMAP is missing source-of-truth entry: $needle"
}

$project = Read-RepoText -RelativePath 'desktop\CloudOS.NativeShell\CloudOS.NativeShell.vcxproj'
Assert-Contains $project '<ClCompile Include="src\main_shell_v2.cpp" />' 'Compiled shell graph no longer contains main_shell_v2.cpp.'
Assert-NotContains $project '<ClCompile Include="src\main.cpp"' 'Historical src/main.cpp unexpectedly returned to the compiled shell graph.'

$suite = Read-RepoText -RelativePath 'scripts\native\test-native-contract-suite.ps1'
foreach ($needle in @(
    'test-stability-readiness-v9-contract.ps1',
    'test-lifecycle-v10-contract.ps1',
    'test-shell-supervisor-v11-contract.ps1',
    'test-performance-visual-v12-contract.ps1',
    'test-transactional-deployment-v13-contract.ps1',
    'test-shell-activation-v14-contract.ps1',
    'test-repository-clarity-v15-contract.ps1'
)) {
    Assert-Contains $suite $needle "Central contract suite is missing: $needle"
}

$build = Read-RepoText -RelativePath 'scripts\native\build-cloudos-native.cmd'
Assert-Contains $build 'test-native-contract-suite.ps1' 'Native build must invoke the central contract suite.'
foreach ($legacyDirectCall in @(
    'test-performance-visual-v12-contract.ps1',
    'test-cloudos-native-shell-contracts.ps1',
    'test-native-release-pipeline-contract.ps1'
)) {
    Assert-NotContains $build $legacyDirectCall "Native build still duplicates an individual contract call: $legacyDirectCall"
}

$legacyLauncher = Read-RepoText -RelativePath 'scripts\native\configure-cloudos-shell-launcher.ps1'
Assert-Contains $legacyLauncher 'LEGACY' 'Old Shell Launcher script must be marked LEGACY.'
Assert-Contains $legacyLauncher 'V14' 'Old Shell Launcher script must point readers to the V14 mechanism.'

$roadmap = Read-RepoText -RelativePath 'docs\native\DESKTOP_SYSTEM_ROADMAP.md'
Assert-Contains $roadmap 'V14' 'Native roadmap must include the current Shell Activation milestone.'
Assert-Contains $roadmap 'V15' 'Native roadmap must include Repository Clarity V15.'

$workflow = Read-RepoText -RelativePath '.github\workflows\cloudos-native-full-system.yml'
Assert-Contains $workflow "- 'AGENTS.md'" 'Full-System CI path filters must include AGENTS.md.'
Assert-Contains $workflow "- 'README.md'" 'Full-System CI path filters must include root README.md.'
Assert-Contains $workflow "- 'docs/ARCHITECTURE.md'" 'Full-System CI path filters must include compatibility architecture docs.'
Assert-Contains $workflow 'test-repository-clarity-v15-contract.ps1' 'Full-System CI must execute the fast V15 repository-clarity gate.'

Write-Host 'PASS: Repository Clarity V15 locks the native source of truth, code map, module guides, central contract suite and legacy boundaries.'
