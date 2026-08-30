$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$fixture = Join-Path $root ('desktop\CloudOS.NativeShell\obj\DiagnosticsTests\' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $fixture -Force | Out-Null
$manifest = Join-Path $fixture 'cloudos-native-manifest.json'
$report = Join-Path $fixture 'report.json'
$collector = Join-Path $PSScriptRoot 'collect-native-diagnostics.ps1'
'{"git_head":"DO_NOT_COLLECT","source_fingerprint_sha256":"DO_NOT_COLLECT","source_tree_dirty":{"secret":"DO_NOT_COLLECT"},"private_notes":"DO_NOT_COLLECT"}' | Set-Content -LiteralPath $manifest
& $collector -Root $fixture -OutputPath $report
$text = Get-Content -LiteralPath $report -Raw
if ($text.Contains('DO_NOT_COLLECT') -or $text.Contains($fixture)) { throw 'Diagnostics leaked unapproved manifest content or a local path.' }
$hash = (Get-FileHash -LiteralPath $report).Hash
$rejected = $false
try { & $collector -Root $fixture -OutputPath $report } catch { $rejected = $true }
if (-not $rejected -or (Get-FileHash -LiteralPath $report).Hash -ne $hash) { throw 'Diagnostics overwrote existing evidence.' }
'{invalid DO_NOT_COLLECT' | Set-Content -LiteralPath $manifest
$corruptReport = Join-Path $fixture 'corrupt-report.json'
& $collector -Root $fixture -OutputPath $corruptReport
$corruptText = Get-Content -LiteralPath $corruptReport -Raw
if (($corruptText | ConvertFrom-Json).build_error -ne 'ManifestUnreadable' -or $corruptText.Contains('DO_NOT_COLLECT')) { throw 'Corrupt manifest diagnostics did not fail safely.' }
Write-Host 'PASS: diagnostics allowlist, corrupt-manifest recovery and evidence overwrite protection.'
