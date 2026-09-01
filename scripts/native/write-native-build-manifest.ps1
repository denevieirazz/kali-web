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
$manifestPath = Join-Path $out 'cloudos-native-manifest.json'
$headStamp = Join-Path $out '.cloudos-build-head'
$fingerprintStamp = Join-Path $out '.cloudos-build-fingerprint'
$fingerprintScript = Join-Path $PSScriptRoot 'get-native-build-fingerprint.ps1'

$runtimeNames = @(
    'CloudOS.exe',
    'CloudOS.NativeRuntime.dll',
    'CloudOS.Supervisor.exe',
    'CloudOS.SystemBroker.exe',
    'CloudOS.BrokerProbe.exe'
)
foreach ($name in $runtimeNames) {
    $required = Join-Path $out $name
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        throw "Cannot write native build manifest; required runtime component missing: $required"
    }
    if ((Get-Item -LiteralPath $required).Length -le 0) {
        throw "Cannot write native build manifest; runtime component is empty: $required"
    }
}
if (-not (Test-Path -LiteralPath $fingerprintScript -PathType Leaf)) {
    throw "Cannot write native build manifest; fingerprint helper missing: $fingerprintScript"
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

$records = foreach ($name in $runtimeNames) {
    $path = Join-Path $out $name
    $item = Get-Item -LiteralPath $path
    [ordered]@{
        name = $name
        size = [Int64]$item.Length
        sha256 = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
    }
}

$manifest = [ordered]@{
    schema = 1
    product = 'CloudOS Native Shell'
    shell_authority = 'C++/Win32'
    recovery_authority = 'CloudOS.Supervisor.exe V11'
    broker_authority = 'CloudOS.SystemBroker.exe V21'
    configuration = $Configuration
    platform = 'x64'
    built_utc = [DateTime]::UtcNow.ToString('o')
    git_head = $head
    source_fingerprint_sha256 = $fingerprint
    browser_runtime = 'Microsoft.Web.WebView2 (Browser only)'
    legacy_react_desktop = $false
    files = @($records)
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
Write-Host "[CloudOS] VERIFIED_RUNTIME_COMPONENTS=$($runtimeNames.Count)"
if ($head) {
    Write-Host "[CloudOS] BUILD_HEAD=$head"
}
