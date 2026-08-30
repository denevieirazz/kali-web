param(
    [string]$Root = $(if (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'cloudos-native-manifest.json')) { $PSScriptRoot } else { (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path }),
    [string]$OutputPath,
    [ValidateRange(0, 3600)][int]$SampleSeconds = 0,
    [ValidateRange(1, 60)][int]$IntervalSeconds = 5
)
$ErrorActionPreference = 'Stop'
$rootPath = (Resolve-Path -LiteralPath $Root).Path
$out = if (Test-Path -LiteralPath (Join-Path $rootPath 'cloudos-native-manifest.json')) { $rootPath } else { Join-Path $rootPath 'desktop\CloudOS.NativeShell\bin\Release' }
if (-not $OutputPath) {
    $OutputPath = Join-Path $env:LOCALAPPDATA ('CloudOS\Diagnostics\native-' + [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N') + '.json')
}
$OutputPath = [IO.Path]::GetFullPath($OutputPath)
if (Test-Path -LiteralPath $OutputPath) { throw 'Diagnostic destination already exists; choose a new file.' }
New-Item -ItemType Directory -Path ([IO.Path]::GetDirectoryName($OutputPath)) -Force | Out-Null
$os = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
$manifestPath = Join-Path $out 'cloudos-native-manifest.json'
$build = $null
$buildError = $null
if (Test-Path -LiteralPath $manifestPath) {
    try {
        $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
        $build = [ordered]@{
            git_head = if ($manifest.git_head -is [string] -and $manifest.git_head -cmatch '^[a-f0-9]{40}$') { $manifest.git_head } else { $null }
            fingerprint = if ($manifest.source_fingerprint_sha256 -is [string] -and $manifest.source_fingerprint_sha256 -cmatch '^[a-f0-9]{64}$') { $manifest.source_fingerprint_sha256 } else { $null }
            source_tree_dirty = if ($manifest.source_tree_dirty -is [bool]) { $manifest.source_tree_dirty } else { $null }
        }
    } catch {
        # A corrupt manifest is precisely when diagnostics are useful. Never
        # copy raw parser errors (which can contain private paths/content).
        $buildError = 'ManifestUnreadable'
    }
}
$artifacts = foreach ($name in @('CloudOS.exe', 'CloudOS.NativeRuntime.dll', 'CloudOS.Recovery.exe')) {
    $path = Join-Path $out $name
    $exists = Test-Path -LiteralPath $path -PathType Leaf
    [ordered]@{
        name = $name
        exists = $exists
        bytes = if ($exists) { (Get-Item -LiteralPath $path).Length } else { 0 }
        sha256 = if ($exists) { (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() } else { $null }
        signature = if ($exists) { (Get-AuthenticodeSignature -LiteralPath $path).Status.ToString() } else { 'Missing' }
    }
}
$samples = [Collections.Generic.List[object]]::new()
$session = [Diagnostics.Process]::GetCurrentProcess().SessionId
$timer = [Diagnostics.Stopwatch]::StartNew()
do {
    $processes = @(Get-Process -Name CloudOS -ErrorAction SilentlyContinue | Where-Object {
        $_.SessionId -eq $session -and $_.Path -eq (Join-Path $out 'CloudOS.exe')
    })
    $metrics = foreach ($process in $processes) {
        try {
            [ordered]@{
                pid = $process.Id
                cpu_seconds = $process.TotalProcessorTime.TotalSeconds
                working_set_bytes = $process.WorkingSet64
                private_bytes = $process.PrivateMemorySize64
                threads = $process.Threads.Count
                handles = $process.HandleCount
                responding = $process.Responding
            }
        } catch { [ordered]@{ pid = $process.Id; exited_during_sample = $true } }
    }
    $samples.Add([ordered]@{ elapsed_seconds = [Math]::Round($timer.Elapsed.TotalSeconds, 3); processes = @($metrics) })
    if ($timer.Elapsed.TotalSeconds -ge $SampleSeconds) { break }
    Start-Sleep -Milliseconds ([int](1000 * [Math]::Min($IntervalSeconds, $SampleSeconds - $timer.Elapsed.TotalSeconds)))
} while ($true)
$report = [ordered]@{
    schema = 1
    collected_utc = [DateTime]::UtcNow.ToString('o')
    privacy = 'Allowlisted local metadata only. No window titles, filenames from user folders, command lines, URLs, credentials, session contents, logs or memory dumps. No upload.'
    windows = [ordered]@{ build = $os.CurrentBuild; revision = $os.UBR; display_version = $os.DisplayVersion }
    logical_processors = [Environment]::ProcessorCount
    build = $build
    build_error = $buildError
    artifacts = @($artifacts)
    samples = $samples.ToArray()
}
$json = $report | ConvertTo-Json -Depth 10
# CreateNew also prevents a race from overwriting another report.
$stream = [IO.File]::Open($OutputPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
try {
    $bytes = [Text.Encoding]::UTF8.GetBytes($json)
    $stream.Write($bytes, 0, $bytes.Length)
} finally { $stream.Dispose() }
Write-Host "PASS: local diagnostics saved ($($samples.Count) samples). No data uploaded."
