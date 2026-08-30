param(
    [string]$Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path,
    [ValidateSet('Release', 'Debug')]
    [string]$Configuration = 'Release',
    [string]$BuildDirectory
)

$ErrorActionPreference = 'Stop'

$rootPath = (Resolve-Path -LiteralPath $Root).Path
$out = Join-Path $rootPath "desktop\CloudOS.NativeShell\bin\$Configuration"
if ($BuildDirectory) { $out = (Resolve-Path -LiteralPath $BuildDirectory).Path }
$exe = Join-Path $out 'CloudOS.exe'
$dll = Join-Path $out 'CloudOS.NativeRuntime.dll'
$manifestPath = Join-Path $out 'cloudos-native-manifest.json'
$headStamp = Join-Path $out '.cloudos-build-head'
$fingerprintStamp = Join-Path $out '.cloudos-build-fingerprint'
$fingerprintScript = Join-Path $PSScriptRoot 'get-native-build-fingerprint.ps1'

foreach ($required in @($exe, $dll, $fingerprintScript)) {
    if (-not (Test-Path -LiteralPath $required)) {
        throw "Cannot write native build manifest; required path missing: $required"
    }
}

$fingerprint = (& $fingerprintScript -Root $rootPath | Select-Object -Last 1).Trim()
if ($fingerprint -notmatch '^[0-9a-f]{64}$') {
    throw "Invalid native source fingerprint: '$fingerprint'"
}

$head = $null
if (Get-Command git.exe -ErrorAction SilentlyContinue) {
    $candidate = (& git.exe -C $rootPath rev-parse HEAD 2>$null | Select-Object -Last 1)
    if ($candidate) {
        $candidate = $candidate.Trim()
        if ($candidate -match '^[0-9a-fA-F]{40}$') {
            $head = $candidate.ToLowerInvariant()
        }
    }
}

$exeItem = Get-Item -LiteralPath $exe
$dllItem = Get-Item -LiteralPath $dll
$exeHash = (Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash.ToLowerInvariant()
$dllHash = (Get-FileHash -LiteralPath $dll -Algorithm SHA256).Hash.ToLowerInvariant()

$manifest = [ordered]@{
    schema = 1
    product = 'CloudOS Native Shell'
    shell_authority = 'C++/Win32'
    configuration = $Configuration
    platform = 'x64'
    built_utc = [DateTime]::UtcNow.ToString('o')
    git_head = $head
    source_fingerprint_sha256 = $fingerprint
    browser_runtime = 'Microsoft.Web.WebView2 (Browser only)'
    legacy_react_desktop = $false
    files = @(
        [ordered]@{
            name = 'CloudOS.exe'
            size = [Int64]$exeItem.Length
            sha256 = $exeHash
        },
        [ordered]@{
            name = 'CloudOS.NativeRuntime.dll'
            size = [Int64]$dllItem.Length
            sha256 = $dllHash
        }
    )
}

$manifest | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $manifestPath -Encoding utf8
Set-Content -LiteralPath $fingerprintStamp -Value $fingerprint -Encoding ascii -NoNewline
if ($head) {
    Set-Content -LiteralPath $headStamp -Value $head -Encoding ascii -NoNewline
}
elseif (Test-Path -LiteralPath $headStamp) {
    Remove-Item -LiteralPath $headStamp -Force
}

Write-Host "[CloudOS] MANIFEST=$manifestPath"
Write-Host "[CloudOS] SOURCE_FINGERPRINT=$fingerprint"
if ($head) {
    Write-Host "[CloudOS] BUILD_HEAD=$head"
}
