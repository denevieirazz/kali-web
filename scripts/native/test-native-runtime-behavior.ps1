param([string]$Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path)
$ErrorActionPreference = 'Stop'
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
$vs = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if (-not $vs) { throw 'MSVC x64 required for native runtime behavior tests.' }
$testOutput = Join-Path $Root 'desktop\CloudOS.NativeShell\obj\BehaviorTests'
New-Item -ItemType Directory -Path $testOutput -Force | Out-Null
$source = Join-Path $Root 'desktop\CloudOS.NativeShell\tests\floating_dock_regression.cpp'
$fixture = Join-Path $testOutput 'floating_dock_regression.exe'
$object = Join-Path $testOutput 'floating_dock_regression.obj'
$include = Join-Path $Root 'desktop\CloudOS.NativeRuntime\include'
$vcvars = Join-Path $vs 'VC\Auxiliary\Build\vcvars64.bat'
$compileScript = Join-Path $testOutput 'compile-fixture.cmd'
@"
@echo off
call "$vcvars"
if errorlevel 1 exit /b %ERRORLEVEL%
cl.exe /nologo /EHsc /std:c++latest /W4 /WX /utf-8 /DUNICODE /D_UNICODE /DNOMINMAX /DWIN32_LEAN_AND_MEAN /D_WIN32_WINNT=0x0A00 /I"$include" "$source" /Fo"$object" /Fe"$fixture" /link user32.lib gdi32.lib
exit /b %ERRORLEVEL%
"@ | Set-Content -LiteralPath $compileScript -Encoding utf8
& cmd.exe /d /c $compileScript
if ($LASTEXITCODE -ne 0) { throw "Behavior fixture compilation failed: $LASTEXITCODE" }
$fixtureLog = Join-Path $testOutput 'fixture.log'
$fixtureErrors = Join-Path $testOutput 'fixture-errors.log'
$process = Start-Process -FilePath $fixture -PassThru -WindowStyle Hidden -RedirectStandardOutput $fixtureLog -RedirectStandardError $fixtureErrors
if (-not $process.WaitForExit(10000)) {
    $process.Kill()
    throw 'Dock runtime regression timed out: possible WinEvent feedback loop.'
}
Get-Content -LiteralPath $fixtureLog
Get-Content -LiteralPath $fixtureErrors
if ($process.ExitCode -ne 0) { throw "Dock runtime regression failed: $($process.ExitCode)" }
