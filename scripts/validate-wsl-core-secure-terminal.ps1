[CmdletBinding()]
param(
  [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]{0,79}$')]
  [string]$Distribution,
  [string]$OutputDirectory = 'test-results\wsl-core-secure-terminal-physical'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$output = [IO.Path]::GetFullPath((Join-Path $root $OutputDirectory))
$coreOutput = Join-Path $output 'core'
$nodeValidation = Join-Path $output 'node-terminal-validation.json'
$validation = Join-Path $output 'validation.json'
New-Item -ItemType Directory -Force -Path $coreOutput | Out-Null
$winDir = if ($env:WINDIR) { $env:WINDIR } else { 'C:\Windows' }
$wsl = Join-Path $winDir 'System32\wsl.exe'
if (-not (Test-Path -LiteralPath $wsl)) { throw 'WSL_NOT_FOUND: wsl.exe is not available.' }

$runId = [Guid]::NewGuid().ToString('N')
$linuxBinary = "/tmp/cloudos-core-secure-$runId"
$linuxGoCache = "/tmp/cloudos-go-cache-$runId"
$linuxModCache = "/tmp/cloudos-go-mod-$runId"
$hostTemp = Join-Path ([IO.Path]::GetTempPath()) "cloudos-wsl-core-secure-$runId"
$databaseCanary = Join-Path $hostTemp 'database-must-not-exist'
$original = @{
  Foundation = [Environment]::GetEnvironmentVariable('CLOUDOS_WSL_CORE_FOUNDATION')
  Terminal = [Environment]::GetEnvironmentVariable('CLOUDOS_WSL_CORE_TERMINAL')
  Fallback = [Environment]::GetEnvironmentVariable('CLOUDOS_WSL_CORE_TERMINAL_FALLBACK')
  CorePath = [Environment]::GetEnvironmentVariable('CLOUDOS_WSL_CORE_LINUX_PATH')
  Data = [Environment]::GetEnvironmentVariable('CLOUDOS_DATA_DIR')
  Db = [Environment]::GetEnvironmentVariable('CLOUDOS_DATABASE_PATH')
}
$selected = $null

function Invoke-Wsl([string[]]$Arguments, [switch]$AllowFailure) {
  $text = & $wsl @Arguments 2>&1
  $exitCode = $LASTEXITCODE
  if (-not $AllowFailure -and $exitCode -ne 0) { throw "WSL_COMMAND_FAILED: exit=$exitCode" }
  [pscustomobject]@{ ExitCode = $exitCode; Output = @($text) }
}

function Get-Wsl2Distributions {
  $result = Invoke-Wsl @('--list','--verbose')
  $items = [System.Collections.Generic.List[object]]::new()
  foreach ($raw in $result.Output) {
    $line = ([string]$raw).Replace([string][char]0, [string]'').Trim()
    if (-not $line) { continue }
    $isDefault = $line.StartsWith('*')
    if ($isDefault) { $line = $line.Substring(1).TrimStart() }
    if ($line -match '^(?<name>[A-Za-z0-9][A-Za-z0-9._-]{0,79})\s+.+?\s+(?<version>[12])$') {
      $items.Add([pscustomobject]@{ Name = $Matches.name; Version = [int]$Matches.version; IsDefault = $isDefault })
    }
  }
  return @($items)
}

function Convert-ToWslPath([string]$WindowsPath) {
  $result = Invoke-Wsl @('--distribution',$selected,'--exec','/usr/bin/wslpath','-a','-u',$WindowsPath)
  $path = (($result.Output | Select-Object -First 1) -as [string]).Trim()
  if (-not $path.StartsWith('/')) { throw 'WSLPATH_FAILED: repository path was not converted.' }
  return $path
}

function Remove-OwnedLinuxPaths {
  if (-not $selected) { return }
  foreach ($path in @($linuxBinary,$linuxGoCache,$linuxModCache)) {
    if ($path -notmatch '^/tmp/cloudos-(?:core-secure|go-cache|go-mod)-[0-9a-f]{32}$') { continue }
    if ($path -eq $linuxBinary) { [void](Invoke-Wsl @('--distribution',$selected,'--exec','/bin/rm','-f',$path) -AllowFailure) }
    else { [void](Invoke-Wsl @('--distribution',$selected,'--exec','/bin/rm','-rf',$path) -AllowFailure) }
  }
}

try {
  $distros = @(Get-Wsl2Distributions)
  if ($distros.Count -eq 0) { throw 'WSL_DISTRO_NOT_FOUND: no installed distributions were detected.' }
  if ($Distribution) {
    $choice = @($distros | Where-Object { $_.Name -ieq $Distribution })
    if ($choice.Count -ne 1) { throw 'DISTRO_NOT_INSTALLED: requested distribution is not installed.' }
    $selected = $choice[0].Name
    if ($choice[0].Version -ne 2) { throw 'DISTRO_NOT_WSL2: requested distribution is not WSL2.' }
  } else {
    $choice = @($distros | Where-Object { $_.Version -eq 2 } | Sort-Object @{Expression={ if ($_.Name -ieq 'kali-linux') {0} elseif ($_.IsDefault) {1} else {2} }}, Name | Select-Object -First 1)
    if ($choice.Count -ne 1) { throw 'DISTRO_NOT_WSL2: no installed WSL2 distribution is available.' }
    $selected = $choice[0].Name
  }

  New-Item -ItemType Directory -Force -Path $hostTemp | Out-Null
  $sourceWindows = Join-Path $root 'core\wsl\cloudos-core'
  $sourceLinux = Convert-ToWslPath $sourceWindows
  $built = $false

  $wslGo = Invoke-Wsl @('--distribution',$selected,'--exec','/usr/bin/env','go','version') -AllowFailure
  if ($wslGo.ExitCode -eq 0) {
    $build = Invoke-Wsl @('--distribution',$selected,'--exec','/usr/bin/env',"GOCACHE=$linuxGoCache","GOMODCACHE=$linuxModCache",'go','-C',$sourceLinux,'build','-trimpath','-o',$linuxBinary,'./cmd/cloudos-core') -AllowFailure
    if ($build.ExitCode -eq 0) { $built = $true }
  }

  if (-not $built) {
    $go = Get-Command go -ErrorAction SilentlyContinue
    if ($null -ne $go) {
      $architectureResult = Invoke-Wsl @('--distribution',$selected,'--exec','/usr/bin/uname','-m')
      $architecture = (($architectureResult.Output | Select-Object -First 1) -as [string]).Trim()
      $goarch = switch ($architecture) { 'x86_64' {'amd64'} 'aarch64' {'arm64'} default { throw "UNSUPPORTED_ARCHITECTURE: $architecture" } }
      $hostBinary = Join-Path $hostTemp 'cloudos-core'
      $hostGoCache = Join-Path $hostTemp 'gocache'
      $hostModCache = Join-Path $hostTemp 'gomodcache'
      $saved = @{ GOOS=$env:GOOS; GOARCH=$env:GOARCH; CGO_ENABLED=$env:CGO_ENABLED; GOCACHE=$env:GOCACHE; GOMODCACHE=$env:GOMODCACHE }
      try {
        $env:GOOS = 'linux'; $env:GOARCH = $goarch; $env:CGO_ENABLED = '0'; $env:GOCACHE = $hostGoCache; $env:GOMODCACHE = $hostModCache
        & $go.Source -C $sourceWindows build -trimpath -o $hostBinary ./cmd/cloudos-core
        if ($LASTEXITCODE -ne 0) { throw 'GO_BUILD_FAILED: Windows cross-build failed.' }
      } finally {
        foreach ($key in $saved.Keys) { [Environment]::SetEnvironmentVariable($key, $saved[$key]) }
      }
      $hostBinaryLinux = Convert-ToWslPath $hostBinary
      [void](Invoke-Wsl @('--distribution',$selected,'--exec','/bin/cp',$hostBinaryLinux,$linuxBinary))
      [void](Invoke-Wsl @('--distribution',$selected,'--exec','/bin/chmod','700',$linuxBinary))
      $built = $true
    }
  }

  if (-not $built) { throw 'GO_NOT_FOUND: Go 1.23+ is required on Windows or in WSL; validation never installs it.' }
  if ((Invoke-Wsl @('--distribution',$selected,'--exec','/usr/bin/test','-x',$linuxBinary) -AllowFailure).ExitCode -ne 0) { throw 'CORE_NOT_EXECUTABLE: temporary cloudos-core binary is not executable.' }
  if ($null -eq (Get-Command dotnet -ErrorAction SilentlyContinue)) { throw 'DOTNET_NOT_FOUND: .NET 8 SDK is required.' }
  if ($null -eq (Get-Command node -ErrorAction SilentlyContinue)) { throw 'NODE_NOT_FOUND: Node.js is required for the Terminal adapter probe.' }

  [Environment]::SetEnvironmentVariable('CLOUDOS_WSL_CORE_FOUNDATION','1')
  [Environment]::SetEnvironmentVariable('CLOUDOS_WSL_CORE_TERMINAL','1')
  [Environment]::SetEnvironmentVariable('CLOUDOS_WSL_CORE_TERMINAL_FALLBACK','0')
  [Environment]::SetEnvironmentVariable('CLOUDOS_WSL_CORE_LINUX_PATH',$linuxBinary)
  [Environment]::SetEnvironmentVariable('CLOUDOS_DATA_DIR',$databaseCanary)
  [Environment]::SetEnvironmentVariable('CLOUDOS_DATABASE_PATH',(Join-Path $databaseCanary 'cloudos.json'))

  & dotnet run --project (Join-Path $root 'desktop\CloudOS.WslCore.Probe\CloudOS.WslCore.Probe.csproj') -c Release -- --distro $selected --core $linuxBinary --output $coreOutput
  if ($LASTEXITCODE -ne 0) { throw "CORE_PHYSICAL_PROBE_FAILED: exit=$LASTEXITCODE" }
  $coreValidation = Join-Path $coreOutput 'validation.json'
  if (-not (Test-Path -LiteralPath $coreValidation)) { throw 'CORE_VALIDATION_MISSING: core validation.json was not produced.' }
  $coreReport = Get-Content -LiteralPath $coreValidation -Raw | ConvertFrom-Json
  if ($coreReport.passed -ne $true -or $coreReport.protocol -ne 2 -or $coreReport.protection -ne 'aes-256-gcm-seq') { throw 'CORE_VALIDATION_FAILED: protected protocol v2 did not pass.' }

  & node (Join-Path $root 'scripts\probe-wsl-core-terminal.mjs') --distro $selected --core $linuxBinary --output $nodeValidation
  if ($LASTEXITCODE -ne 0) { throw "TERMINAL_PHYSICAL_PROBE_FAILED: exit=$LASTEXITCODE" }
  if (-not (Test-Path -LiteralPath $nodeValidation)) { throw 'TERMINAL_VALIDATION_MISSING: Node Terminal validation was not produced.' }
  $terminalReport = Get-Content -LiteralPath $nodeValidation -Raw | ConvertFrom-Json
  if ($terminalReport.passed -ne $true -or $terminalReport.protocol -ne 2 -or $terminalReport.protection -ne 'aes-256-gcm-seq') { throw 'TERMINAL_VALIDATION_FAILED: backend Terminal adapter did not pass.' }

  if (Test-Path -LiteralPath $databaseCanary) { throw 'DATABASE_CANARY_TOUCHED: validation reached the database canary path.' }
  foreach ($report in @($coreReport,$terminalReport)) {
    if ($report.wslMutated -ne $false -or $report.elevationRequested -ne $false -or $report.databaseTouched -ne $false) { throw 'VALIDATION_SAFETY_FAILED: probe reported an excluded mutation.' }
  }

  $pids = @($coreReport.childPids) + @($coreReport.corePid) + @($terminalReport.corePid) + @($terminalReport.terminalPid)
  foreach ($pidValue in @($pids | Where-Object { [int]$_ -gt 0 } | Sort-Object -Unique)) {
    $alive = Invoke-Wsl @('--distribution',$selected,'--exec','/usr/bin/test','-d',"/proc/$pidValue") -AllowFailure
    if ($alive.ExitCode -eq 0) { throw "ORPHAN_PROCESS: Linux PID $pidValue survived shutdown." }
  }

  $final = [ordered]@{
    passed = $true
    physicalValidation = $true
    protocol = 2
    protection = 'aes-256-gcm-seq'
    distribution = $selected
    cgroupV2 = $coreReport.cgroupV2
    coreChecks = @($coreReport.checks)
    terminalChecks = @($terminalReport.checks)
    terminalIntegration = $true
    legacyFallbackPreserved = $true
    noOrphansVerified = $true
    databaseTouched = $false
    wslMutated = $false
    elevationRequested = $false
  }
  $final | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $validation -Encoding utf8
  Write-Host "PASS CloudOS WSL core secure Terminal physical validation: $validation"
}
finally {
  [Environment]::SetEnvironmentVariable('CLOUDOS_WSL_CORE_FOUNDATION',$original.Foundation)
  [Environment]::SetEnvironmentVariable('CLOUDOS_WSL_CORE_TERMINAL',$original.Terminal)
  [Environment]::SetEnvironmentVariable('CLOUDOS_WSL_CORE_TERMINAL_FALLBACK',$original.Fallback)
  [Environment]::SetEnvironmentVariable('CLOUDOS_WSL_CORE_LINUX_PATH',$original.CorePath)
  [Environment]::SetEnvironmentVariable('CLOUDOS_DATA_DIR',$original.Data)
  [Environment]::SetEnvironmentVariable('CLOUDOS_DATABASE_PATH',$original.Db)
  try { Remove-OwnedLinuxPaths } catch { Write-Warning 'Owned Linux temporary path cleanup did not complete.' }
  if (Test-Path -LiteralPath $hostTemp) { Remove-Item -LiteralPath $hostTemp -Recurse -Force -ErrorAction SilentlyContinue }
}
