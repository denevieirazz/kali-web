param(
    [string]$Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path,
    [switch]$CompileOnly
)
$ErrorActionPreference = 'Stop'
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
$vs = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if (-not $vs) { throw 'MSVC required.' }
$directory = Join-Path $Root 'desktop\CloudOS.NativeShell\bin\UX-Release'
$intermediate = Join-Path $Root 'desktop\CloudOS.NativeShell\obj\SurfaceTests'
New-Item -ItemType Directory -Force -Path $directory, $intermediate | Out-Null
$source = Join-Path $Root 'desktop\CloudOS.NativeShell\tests\native_surface_preview.cpp'
$fixture = Join-Path $directory 'CloudOS.SurfacePreview.exe'
$include = Join-Path $Root 'desktop\CloudOS.NativeRuntime\include'
$project = [xml](Get-Content -Raw -LiteralPath (Join-Path $Root 'desktop\CloudOS.NativeShell\CloudOS.NativeShell.vcxproj'))
$objects = foreach ($entry in $project.Project.ItemGroup.ClCompile) {
    if ($entry.Include -and $entry.Include -ne 'src\main_shell_v2.cpp') {
        Get-Item -LiteralPath (Join-Path $Root ('desktop\CloudOS.NativeShell\obj\Release\' + [IO.Path]::GetFileNameWithoutExtension($entry.Include) + '.obj'))
    }
}
if ($objects.Count -lt 40) { throw 'Build the Release shell before compiling its surface fixture.' }
$loader = Get-ChildItem -LiteralPath (Join-Path $Root 'desktop\CloudOS.NativeShell\packages') -Recurse -Filter 'WebView2LoaderStatic.lib' |
    Where-Object FullName -Match '\\x64\\' | Select-Object -First 1
if (-not $loader) { throw 'Restored WebView2 x64 loader missing.' }
$response = Join-Path $intermediate 'link.rsp'
$arguments = @('/SUBSYSTEM:CONSOLE', '/LTCG', ('/OUT:"'+$fixture+'"'),
    ('"'+(Join-Path $intermediate 'preview.obj')+'"'),
    ('"'+(Join-Path $Root 'desktop\CloudOS.NativeRuntime\bin\Release\CloudOS.NativeRuntime.lib')+'"'),
    ('"'+$loader.FullName+'"'),
    '/MANIFEST:EMBED', ('/MANIFESTINPUT:"'+(Join-Path $Root 'desktop\CloudOS.NativeShell\app.manifest')+'"'),
    'user32.lib gdi32.lib dwmapi.lib shell32.lib ole32.lib uuid.lib advapi32.lib comdlg32.lib comctl32.lib gdiplus.lib dxva2.lib iphlpapi.lib powrprof.lib psapi.lib propsys.lib wlanapi.lib wbemuuid.lib windowscodecs.lib ws2_32.lib shlwapi.lib')
$arguments += $objects | ForEach-Object { '"'+$_.FullName+'"' }
[IO.File]::WriteAllLines($response, $arguments)
$compile = Join-Path $intermediate 'compile.cmd'
$vcvars = Join-Path $vs 'VC\Auxiliary\Build\vcvars64.bat'
@"
@echo off
call "$vcvars"
if errorlevel 1 exit /b %ERRORLEVEL%
cl.exe /nologo /c /MD /EHsc /std:c++latest /W4 /WX /utf-8 /DUNICODE /D_UNICODE /DNOMINMAX /DWIN32_LEAN_AND_MEAN /D_WIN32_WINNT=0x0A00 /FIwindowsx.h /FIobjbase.h /FIpropkeydef.h /I"$include" "$source" /Fo"$intermediate\preview.obj"
if errorlevel 1 exit /b %ERRORLEVEL%
link.exe @"$response"
exit /b %ERRORLEVEL%
"@ | Set-Content -LiteralPath $compile -Encoding utf8
& cmd.exe /d /c $compile
if ($LASTEXITCODE -ne 0) { throw "Native surface fixture build failed: $LASTEXITCODE" }
if (-not $CompileOnly) {
    & $fixture --test
    if ($LASTEXITCODE -ne 0) { throw "Native surface regression failed: $LASTEXITCODE" }
}
