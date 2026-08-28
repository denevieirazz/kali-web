[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$bridgePath = Join-Path $repoRoot 'desktop\CloudOS.Host\Bridge\WebMessageBridge.cs'
$content = [IO.File]::ReadAllText($bridgePath)

$old = '        if (CapturedSurfaceBridgeAdapter.CandidateEnabled)'
$new = @'
        if (NativeSurfaceMode.Current == NativeSurfaceRenderMode.CapturedSurface
            && CapturedSurfaceBridgeAdapter.CandidateEnabled)
'@.TrimEnd("`r", "`n")

$count = ([regex]::Matches($content, [regex]::Escape($old))).Count
if ($count -ne 1) {
    throw "EXPECTED_ONE_CAPTURE_INITIALIZER_FOUND_$count"
}

$content = $content.Replace($old, $new)
[IO.File]::WriteAllText($bridgePath, $content, [Text.UTF8Encoding]::new($false))

$updated = [IO.File]::ReadAllText($bridgePath)
if (-not $updated.Contains('NativeSurfaceMode.Current == NativeSurfaceRenderMode.CapturedSurface')) {
    throw 'NATIVE_SURFACE_MODE_GUARD_MISSING'
}
if ($updated.Contains('        if (CapturedSurfaceBridgeAdapter.CandidateEnabled)')) {
    throw 'UNGUARDED_CAPTURE_INITIALIZER_REMAINS'
}

Write-Host 'NATIVE_SURFACE_DEFAULT_PATCHED'
