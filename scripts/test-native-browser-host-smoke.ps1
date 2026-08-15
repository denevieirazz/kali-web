param(
    [switch]$AllowNonCi
)

. (Join-Path $PSScriptRoot 'require-powershell7-windows.ps1')

$smokeCore = Join-Path $PSScriptRoot 'test-native-browser-host-smoke-core.ps1'
if (-not (Test-Path -LiteralPath $smokeCore)) {
    throw "SMOKE_CORE_MISSING: implementação do smoke ausente em $smokeCore"
}

& $smokeCore -AllowNonCi:$AllowNonCi
