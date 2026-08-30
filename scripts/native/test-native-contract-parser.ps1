$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'native-contract-source.ps1')

$cases = @(
    @{ Name = 'documented absent dependency'; Code = '// SDK does not ship oledb32.lib'; Forbidden = $false },
    @{ Name = 'block comment'; Code = '/* #pragma comment(lib, "oledb32.lib") */'; Forbidden = $false },
    @{ Name = 'actual import'; Code = '#pragma comment(lib, "oledb32.lib")'; Forbidden = $true },
    @{ Name = 'import after a comment'; Code = '/* explanation */ #pragma comment(lib, "oledb32.lib")'; Forbidden = $true },
    @{ Name = 'comment markers inside strings'; Code = 'const char* url = "https://example.test/*path*/"; #pragma comment(lib, "oledb32.lib")'; Forbidden = $true },
    @{ Name = 'escaped quote'; Code = 'const char* text = "\"//"; #pragma comment(lib, "oledb32.lib")'; Forbidden = $true },
    @{ Name = 'raw string'; Code = 'auto s = R"tag(// " /* oledb32.lib */)tag";'; Forbidden = $true },
    @{ Name = 'continued comment'; Code = "// explanation \`n#pragma comment(lib, `"oledb32.lib`")"; Forbidden = $false },
    @{ Name = 'continued import'; Code = "#pragma comment(lib, `"oledb32.\`nlib`")"; Forbidden = $true }
)
foreach ($case in $cases) {
    $actual = (Remove-NativeCppComments $case.Code).Contains('oledb32.lib')
    if ($actual -ne $case.Forbidden) { throw "C++ comment parser regression: $($case.Name)" }
}
Write-Host "PASS: $($cases.Count) C++ comment/literal regression cases; comments do not hide actual forbidden dependencies."
