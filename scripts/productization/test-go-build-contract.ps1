Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'common.ps1')
$root=Get-CloudOSRepoRoot
$coreRoot=Join-Path $root 'core/wsl/cloudos-core'
$mainPath=Join-Path $coreRoot 'cmd/cloudos-core/main.go'
$buildPath=Join-Path $root 'scripts/productization/build-cloudos.ps1'
$workflowPath=Join-Path $root '.github/workflows/productization-batch2-ci.yml'

if(-not(Test-Path -LiteralPath $mainPath -PathType Leaf)){throw 'CLOUDOS_CORE_MAIN_MISSING'}
$main=Get-Content -LiteralPath $mainPath -Raw
if($main -notmatch '(?m)^package\s+main\s*$'){throw 'CLOUDOS_CORE_PACKAGE_NOT_MAIN'}
if($main -notmatch '(?m)^func\s+main\s*\('){throw 'CLOUDOS_CORE_MAIN_FUNCTION_MISSING'}

$rootGoFiles=@(Get-ChildItem -LiteralPath $coreRoot -File -Filter '*.go')
if($rootGoFiles.Count -ne 0){throw 'CLOUDOS_CORE_ROOT_UNEXPECTED_GO_FILES'}

$go=Get-CloudOSCommandName 'go'
$packageInfo=Invoke-CloudOSExternal $go @('list','-f','{{.Name}}|{{.ImportPath}}','./cmd/cloudos-core') $coreRoot -Capture
$packageLine=@($packageInfo.Output -split "`r?`n" | Where-Object {$_ -match '^main\|'}) | Select-Object -Last 1
$expectedPackage='main|github.com/denevieirazz/kali-web/core/wsl/cloudos-core/cmd/cloudos-core'
if([string]$packageLine -ne $expectedPackage){throw "CLOUDOS_CORE_MAIN_PACKAGE_UNEXPECTED:$($packageInfo.Output)"}

$build=Get-Content -LiteralPath $buildPath -Raw
$workflow=Get-Content -LiteralPath $workflowPath -Raw
if($build -notmatch [regex]::Escape("`$corePackage = './cmd/cloudos-core'")){throw 'CLOUDOS_CORE_BUILD_PACKAGE_NOT_EXPLICIT'}
if($build -notmatch [regex]::Escape("`$coreOutput = Join-Path `$paths.Build 'cloudos-core-linux-amd64'")){throw 'CLOUDOS_CORE_BUILD_OUTPUT_NOT_DETERMINISTIC'}
if($build -notmatch [regex]::Escape("`$env:GOOS='linux'")){throw 'CLOUDOS_CORE_GOOS_NOT_LINUX'}
if($build -notmatch [regex]::Escape("`$env:GOARCH='amd64'")){throw 'CLOUDOS_CORE_GOARCH_NOT_AMD64'}
if($build -notmatch [regex]::Escape("`$env:CGO_ENABLED='0'")){throw 'CLOUDOS_CORE_CGO_NOT_DISABLED'}
$linuxGuard='if (-not $IsWindows) {'
$testCall="Invoke-CloudOSExternal `$go @('test','./...') `$coreRoot"
$linuxGuardIndex=$build.IndexOf($linuxGuard,[StringComparison]::Ordinal)
$testIndex=$build.IndexOf($testCall,[StringComparison]::Ordinal)
$targetIndex=$build.IndexOf("`$env:GOOS='linux'",[StringComparison]::Ordinal)
if($linuxGuardIndex -lt 0 -or $testIndex -lt 0 -or $testIndex -lt $linuxGuardIndex){throw 'CLOUDOS_CORE_LINUX_HOST_TEST_MISSING'}
if($targetIndex -lt 0 -or $testIndex -gt $targetIndex){throw 'CLOUDOS_CORE_TEST_MUST_PRECEDE_CROSS_BUILD'}
if($build -notmatch [regex]::Escape("Invoke-CloudOSExternal `$go @('build','-trimpath','-ldflags=-buildid=','-o',`$coreOutput,`$corePackage) `$coreRoot")){throw 'CLOUDOS_CORE_BUILD_COMMAND_CHANGED'}
if($workflow -notmatch '(?ms)linux-compatible:.*?- name: Go core tests\s+working-directory: core/wsl/cloudos-core\s+run: go test \.\/\.\.\.'){throw 'CLOUDOS_CORE_CI_LINUX_TEST_MISSING'}
if($workflow -notmatch '(?ms)windows-product:\s+needs:\s+linux-compatible'){throw 'CLOUDOS_CORE_WINDOWS_MUST_DEPEND_ON_LINUX_TESTS'}

$forbidden=@(
    "@('build','-trimpath','-ldflags=-buildid=','-o',`$coreOutput,'.')",
    "@('build','-o',`$coreOutput,'.')",
    "go build ."
)
foreach($pattern in $forbidden){if($build.IndexOf($pattern,[StringComparison]::OrdinalIgnoreCase) -ge 0){throw "CLOUDOS_CORE_ROOT_BUILD_FORBIDDEN:$pattern"}}

Write-Host 'PRODUCTIZATION_GO_BUILD_CONTRACT_OK package=./cmd/cloudos-core target=linux/amd64 tests=linux-before-windows'
