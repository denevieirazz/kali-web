$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$fixture = Join-Path $root ('desktop\CloudOS.NativeShell\obj\FingerprintTests\' + [guid]::NewGuid().ToString('N'))
foreach ($relative in @('desktop\CloudOS.NativeRuntime', 'desktop\CloudOS.NativeShell', 'desktop\CloudOS.NativeRecovery', 'scripts\native')) {
    New-Item -ItemType Directory -Path (Join-Path $fixture $relative) -Force | Out-Null
}
$source = Join-Path $fixture 'desktop\CloudOS.NativeRecovery\main.cpp'
'int version = 1;' | Set-Content -LiteralPath $source
$fingerprint = Join-Path $PSScriptRoot 'get-native-build-fingerprint.ps1'
$before = & $fingerprint -Root $fixture
$artifacts = Join-Path $fixture 'desktop\CloudOS.NativeShell\artifacts'
New-Item -ItemType Directory -Path $artifacts -Force | Out-Null
'generated package metadata' | Set-Content -LiteralPath (Join-Path $artifacts 'cloudos-native-manifest.json')
'generated ZIP payload' | Set-Content -LiteralPath (Join-Path $artifacts 'CloudOS.zip')
$afterPackage = & $fingerprint -Root $fixture
if ($before -ne $afterPackage) { throw 'Generated release artifacts changed the source fingerprint.' }
'int version = 2;' | Set-Content -LiteralPath $source
$afterSourceEdit = & $fingerprint -Root $fixture
if ($before -eq $afterSourceEdit) { throw 'Recovery source edit did not invalidate the source fingerprint.' }
Write-Host 'PASS: packaging does not invalidate source provenance; Recovery source edits do.'
