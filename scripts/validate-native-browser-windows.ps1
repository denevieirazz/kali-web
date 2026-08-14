param(
    [switch]$DisposableProfile
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if (-not $IsWindows) {
    throw 'Este validador exige Windows com WebView2 Runtime.'
}
if (-not $DisposableProfile) {
    throw 'Use -DisposableProfile somente em Windows Sandbox/VM descartável. O smoke completo não roda contra perfil CloudOS real.'
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$cloudRoot = Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)) 'CloudOS'
if (Test-Path -LiteralPath $cloudRoot) {
    throw 'PROFILE_NOT_DISPOSABLE: %LOCALAPPDATA%\CloudOS já existe. Use uma Windows Sandbox/VM limpa.'
}

function Invoke-Gate {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][scriptblock]$Command
    )
    Write-Host "`n=== $Name ===" -ForegroundColor Cyan
    & $Command
    if ($LASTEXITCODE -ne 0) {
        throw "$Name falhou com código $LASTEXITCODE."
    }
}

Push-Location $repoRoot
try {
    Invoke-Gate 'npm ci' { npm.cmd ci }
    Invoke-Gate 'Playwright Chromium' { npx.cmd playwright install chromium }
    Invoke-Gate 'Lint' { npm.cmd run lint }
    Invoke-Gate 'Frontend build' { npm.cmd run build }
    Invoke-Gate 'Backend/integration' { npm.cmd test }
    Invoke-Gate 'Node E2E' { npm.cmd run test:e2e }
    Invoke-Gate 'Frontend unit' { node scripts/run-node-tests.js frontend/test }

    Invoke-Gate 'CloudOS.Host build' { dotnet build desktop/CloudOS.Host/CloudOS.Host.csproj -c Release }
    Invoke-Gate 'CloudOS.Host.Tests' { dotnet run --project desktop/CloudOS.Host.Tests/CloudOS.Host.Tests.csproj -c Release }
    Invoke-Gate 'Browser response contracts' { dotnet run --project desktop/CloudOS.Browser.Contracts.Tests/CloudOS.Browser.Contracts.Tests.csproj -c Release }
    Invoke-Gate 'Host/bundle freshness policy' { pwsh -NoProfile -File scripts/test-native-host-freshness.ps1 }
    Invoke-Gate 'Bootstrap build' { dotnet build desktop/CloudOS.Bootstrap/CloudOS.Bootstrap.csproj -c Release }
    Invoke-Gate 'Bootstrap.Tests' { dotnet run --project desktop/CloudOS.Bootstrap.Tests/CloudOS.Bootstrap.Tests.csproj -c Release }
    Invoke-Gate 'Browser TestHost build' { dotnet build desktop/CloudOS.Browser.TestHost/CloudOS.Browser.TestHost.csproj -c Release }

    Invoke-Gate 'Playwright characterization' {
        npx.cmd playwright test --grep-invert 'Navegador CloudOS — WebView2 real|Navegador CloudOS — lifecycle Windows'
    }
    Invoke-Gate 'Browser opening lifecycle' {
        npx.cmd playwright test tests/playwright/native-browser-lifecycle.spec.ts --output=test-results/native-browser-lifecycle --reporter=list
    }
    Invoke-Gate 'Native Browser WebView2' {
        npx.cmd playwright test tests/playwright/native-browser.spec.ts --output=test-results/native-browser --reporter=list
    }
    Invoke-Gate 'Native Host Browser smoke' {
        pwsh -NoProfile -File scripts/test-native-browser-host-smoke.ps1 -AllowNonCi
    }
    Invoke-Gate 'Diff whitespace' {
        git fetch origin integration/cloudos-foundation --no-tags
        git diff --check origin/integration/cloudos-foundation...HEAD
    }

    Write-Host "`nPASS validate-native-browser-windows" -ForegroundColor Green
}
finally {
    Pop-Location
}
