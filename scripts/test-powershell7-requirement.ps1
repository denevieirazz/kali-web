$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$requireScript = Join-Path $PSScriptRoot 'require-powershell7-windows.ps1'
$validatorScript = Join-Path $PSScriptRoot 'validate-native-browser-windows.ps1'
$smokeScript = Join-Path $PSScriptRoot 'test-native-browser-host-smoke.ps1'
$legacyPowerShell = (Get-Command powershell.exe -ErrorAction Stop).Source

if (Get-Variable -Name PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue) {
    $PSNativeCommandUseErrorActionPreference = $false
}

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

function Invoke-WindowsPowerShellScript {
    param(
        [Parameter(Mandatory = $true)][string]$ScriptPath,
        [string[]]$Arguments = @()
    )

    $output = @(& $legacyPowerShell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $ScriptPath @Arguments 2>&1)
    $exitCode = $LASTEXITCODE
    return [PSCustomObject]@{
        ExitCode = $exitCode
        Text = ($output | Out-String)
    }
}

# Positive preflight: the same helper must accept the current pwsh session.
. $requireScript
Assert-True ($PSVersionTable.PSEdition -eq 'Core') 'O teste de requisito deve executar em PowerShell Core.'
Assert-True ($PSVersionTable.PSVersion -ge [Version]'7.2') 'O teste de requisito exige pwsh 7.2+.'

# Static order: version/edition failure must be declared before the helper ever reads $IsWindows.
$requireContent = Get-Content -LiteralPath $requireScript -Raw
$requiredIndex = $requireContent.IndexOf('POWERSHELL_7_REQUIRED', [StringComparison]::Ordinal)
$isWindowsIndex = $requireContent.IndexOf('$IsWindows', [StringComparison]::Ordinal)
Assert-True ($requiredIndex -ge 0) 'Preflight não contém POWERSHELL_7_REQUIRED.'
Assert-True ($isWindowsIndex -gt $requiredIndex) 'O helper acessa $IsWindows antes de validar PowerShell 7.2+.'

# Windows PowerShell 5.1 must fail immediately and clearly for both public entrypoints.
$validatorLegacy = Invoke-WindowsPowerShellScript -ScriptPath $validatorScript -Arguments @('-DisposableProfile')
Assert-True ($validatorLegacy.ExitCode -ne 0) 'Windows PowerShell 5.1 não deveria executar o validador.'
Assert-True ($validatorLegacy.Text -match 'POWERSHELL_7_REQUIRED') 'Validador 5.1 não informou POWERSHELL_7_REQUIRED.'
Assert-True ($validatorLegacy.Text -match 'Windows PowerShell 5\.1') 'Validador 5.1 não informou o runtime detectado.'

$smokeLegacy = Invoke-WindowsPowerShellScript -ScriptPath $smokeScript -Arguments @('-AllowNonCi')
Assert-True ($smokeLegacy.ExitCode -ne 0) 'Windows PowerShell 5.1 não deveria executar o smoke.'
Assert-True ($smokeLegacy.Text -match 'POWERSHELL_7_REQUIRED') 'Smoke 5.1 não informou POWERSHELL_7_REQUIRED.'
Assert-True ($smokeLegacy.Text -match 'Windows PowerShell 5\.1') 'Smoke 5.1 não informou o runtime detectado.'

# Once inside pwsh, child PowerShell scripts must stay in the current session instead of requiring pwsh in PATH.
$validatorContent = Get-Content -LiteralPath $validatorScript -Raw
Assert-True ($validatorContent -notmatch '(?im)^\s*(?:&\s+)?pwsh(?:\.exe)?\s+-NoProfile') 'Validador ainda cria processo pwsh desnecessário.'
Assert-True ($validatorContent -match '& \$freshnessScript') 'Freshness deve executar na sessão PowerShell atual.'
Assert-True ($validatorContent -match '& \$smokeScript -AllowNonCi') 'Smoke deve executar na sessão PowerShell atual.'

# The two intentional Windows PowerShell failures leave LASTEXITCODE=1; reset it after asserting them.
$global:LASTEXITCODE = 0
Write-Host 'PASS PowerShell 7 runtime requirement'
