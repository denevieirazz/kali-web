$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot 'require-powershell7-windows.ps1')

$baseSha = 'f83a765061eb69df2f88a162c44ef0ec7dc60b90'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$outputRoot = Join-Path $repoRoot 'test-results/native-browser-visual'
$projectPath = Join-Path $repoRoot 'desktop/CloudOS.Browser.VisualCapture/CloudOS.Browser.VisualCapture.csproj'
$metricsPath = Join-Path $outputRoot 'visual-metrics.txt'
$beforePath = Join-Path $outputRoot 'before-legacy-wide.png'
$afterDarkPath = Join-Path $outputRoot 'after-dark-wide.png'
$afterLightPath = Join-Path $outputRoot 'after-light-wide.png'
$afterCompactPath = Join-Path $outputRoot 'after-dark-compact.png'
$beforeDiffPath = Join-Path $outputRoot 'diff-before-vs-dark.png'
$themeDiffPath = Join-Path $outputRoot 'diff-dark-vs-light.png'

Remove-Item $outputRoot -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Path $outputRoot -Force | Out-Null

function Invoke-DotnetChecked {
    param([Parameter(Mandatory = $true)][string[]]$Arguments)
    & dotnet @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "NATIVE_BROWSER_VISUAL_FAILED: dotnet $($Arguments -join ' ') retornou $LASTEXITCODE."
    }
}

function Invoke-Capture {
    param(
        [Parameter(Mandatory = $true)][string]$Project,
        [Parameter(Mandatory = $true)][string]$Output,
        [Parameter(Mandatory = $true)][string]$Theme,
        [Parameter(Mandatory = $true)][int]$Width,
        [Parameter(Mandatory = $true)][int]$Height
    )
    Invoke-DotnetChecked @('run', '--project', $Project, '-c', 'Release', '--no-build', '--', 'capture', $Output, $Theme, "$Width", "$Height")
}

Invoke-DotnetChecked @('build', $projectPath, '-c', 'Release')
Invoke-Capture -Project $projectPath -Output $afterDarkPath -Theme 'dark' -Width 1280 -Height 820
Invoke-Capture -Project $projectPath -Output $afterLightPath -Theme 'light' -Width 1280 -Height 820
Invoke-Capture -Project $projectPath -Output $afterCompactPath -Theme 'dark' -Width 820 -Height 620

$worktreeParent = if ($env:RUNNER_TEMP) { $env:RUNNER_TEMP } else { [System.IO.Path]::GetTempPath() }
$baseWorktree = Join-Path $worktreeParent "cloudos-browser-visual-base-$([Guid]::NewGuid().ToString('N'))"

try {
    & git -C $repoRoot worktree add --detach $baseWorktree $baseSha
    if ($LASTEXITCODE -ne 0) {
        throw "NATIVE_BROWSER_VISUAL_FAILED: não foi possível criar worktree do baseline $baseSha."
    }

    $baseCaptureDir = Join-Path $baseWorktree 'desktop/CloudOS.Browser.VisualCapture'
    New-Item -ItemType Directory -Path $baseCaptureDir -Force | Out-Null
    Copy-Item (Join-Path $repoRoot 'desktop/CloudOS.Browser.VisualCapture/*') $baseCaptureDir -Force
    $baseProject = Join-Path $baseCaptureDir 'CloudOS.Browser.VisualCapture.csproj'

    Invoke-DotnetChecked @('build', $baseProject, '-c', 'Release')
    Invoke-Capture -Project $baseProject -Output $beforePath -Theme 'legacy' -Width 1280 -Height 820
}
finally {
    if (Test-Path $baseWorktree) {
        & git -C $repoRoot worktree remove --force $baseWorktree | Out-Null
    }
}

$beforeMetrics = & dotnet run --project $projectPath -c Release --no-build -- compare $beforePath $afterDarkPath 0.035 $beforeDiffPath
if ($LASTEXITCODE -ne 0) { throw 'NATIVE_BROWSER_VISUAL_FAILED: a reformulação não produziu diferença visual material contra o baseline.' }
$beforeMetrics | Tee-Object -FilePath $metricsPath

$themeMetrics = & dotnet run --project $projectPath -c Release --no-build -- compare $afterDarkPath $afterLightPath 0.08 $themeDiffPath
if ($LASTEXITCODE -ne 0) { throw 'NATIVE_BROWSER_VISUAL_FAILED: temas claro e escuro não ficaram visualmente distintos.' }
$themeMetrics | Tee-Object -FilePath $metricsPath -Append

$required = @($beforePath, $afterDarkPath, $afterLightPath, $afterCompactPath, $beforeDiffPath, $themeDiffPath)
foreach ($path in $required) {
    if (-not (Test-Path $path) -or (Get-Item $path).Length -lt 1024) {
        throw "NATIVE_BROWSER_VISUAL_FAILED: screenshot ausente ou inválido: $path"
    }
}

Write-Host 'PASS native Browser WPF visual comparison'
Write-Host "Visual artifacts: $outputRoot"
