Set-StrictMode -Version Latest

function Invoke-CloudOSWsl {
  param([Parameter(Mandatory)][string]$WslExe,[Parameter(Mandatory)][string[]]$Arguments,[switch]$AllowFailure)
  $output = & $WslExe @Arguments 2>&1
  $exitCode = $LASTEXITCODE
  if (-not $AllowFailure -and $exitCode -ne 0) { throw "WSL_COMMAND_FAILED: exit=$exitCode" }
  [pscustomobject]@{ ExitCode=$exitCode; Output=@($output) }
}

function Get-CloudOSWsl2Distribution {
  param([Parameter(Mandatory)][string]$WslExe,[string]$Requested)
  $list = Invoke-CloudOSWsl -WslExe $WslExe -Arguments @('--list','--verbose')
  $items = @()
  foreach ($raw in $list.Output) {
    $line = ([string]$raw).Replace([string][char]0,'').Trim()
    if (-not $line) { continue }
    $isDefault = $line.StartsWith('*')
    if ($isDefault) { $line=$line.Substring(1).TrimStart() }
    if ($line -match '^(?<name>[A-Za-z0-9][A-Za-z0-9._-]{0,79})\s+.+?\s+(?<version>[12])$') {
      $items += [pscustomobject]@{ Name=$Matches.name; Version=[int]$Matches.version; IsDefault=$isDefault }
    }
  }
  if ($Requested) {
    $match = @($items | Where-Object { $_.Name -ieq $Requested })
    if ($match.Count -ne 1) { throw 'DISTRO_NOT_INSTALLED' }
    if ($match[0].Version -ne 2) { throw 'DISTRO_NOT_WSL2' }
    return $match[0].Name
  }
  $choice = @($items | Where-Object Version -eq 2 | Sort-Object @{Expression={if($_.Name -ieq 'kali-linux'){0}elseif($_.IsDefault){1}else{2}}},Name | Select-Object -First 1)
  if ($choice.Count -ne 1) { throw 'WSL2_DISTRO_NOT_FOUND' }
  return $choice[0].Name
}

function ConvertTo-CloudOSWslPath {
  param([Parameter(Mandatory)][string]$WslExe,[Parameter(Mandatory)][string]$Distribution,[Parameter(Mandatory)][string]$WindowsPath)
  $result = Invoke-CloudOSWsl -WslExe $WslExe -Arguments @('--distribution',$Distribution,'--exec','/usr/bin/wslpath','-a','-u',$WindowsPath)
  $value = (($result.Output | Select-Object -First 1) -as [string]).Trim()
  if (-not $value.StartsWith('/')) { throw 'WSLPATH_FAILED' }
  return $value
}

function New-CloudOSTemporaryCore {
  param([Parameter(Mandatory)][string]$Root,[Parameter(Mandatory)][string]$WslExe,[Parameter(Mandatory)][string]$Distribution,[Parameter(Mandatory)][string]$RunId)
  $linuxBinary = "/tmp/cloudos-core-visible-terminal-$RunId"
  $sourceWindows = Join-Path $Root 'core\wsl\cloudos-core'
  $sourceLinux = ConvertTo-CloudOSWslPath -WslExe $WslExe -Distribution $Distribution -WindowsPath $sourceWindows
  $goCache = "/tmp/cloudos-visible-go-cache-$RunId"
  $modCache = "/tmp/cloudos-visible-go-mod-$RunId"
  $built = $false
  $wslGo = Invoke-CloudOSWsl -WslExe $WslExe -Arguments @('--distribution',$Distribution,'--exec','/usr/bin/env','go','version') -AllowFailure
  if ($wslGo.ExitCode -eq 0) {
    $build = Invoke-CloudOSWsl -WslExe $WslExe -Arguments @('--distribution',$Distribution,'--exec','/usr/bin/env',"GOCACHE=$goCache","GOMODCACHE=$modCache",'go','-C',$sourceLinux,'build','-trimpath','-o',$linuxBinary,'./cmd/cloudos-core') -AllowFailure
    if ($build.ExitCode -eq 0) { $built=$true }
  }
  if (-not $built) {
    $go = Get-Command go -ErrorAction SilentlyContinue
    if (-not $go) { throw 'GO_NOT_FOUND' }
    $archResult = Invoke-CloudOSWsl -WslExe $WslExe -Arguments @('--distribution',$Distribution,'--exec','/usr/bin/uname','-m')
    $arch=(($archResult.Output | Select-Object -First 1) -as [string]).Trim()
    $goarch = if ($arch -eq 'x86_64') {'amd64'} elseif ($arch -eq 'aarch64') {'arm64'} else { throw "UNSUPPORTED_ARCHITECTURE:$arch" }
    $hostTemp = Join-Path ([IO.Path]::GetTempPath()) "cloudos-visible-core-$RunId"
    New-Item -ItemType Directory -Force -Path $hostTemp | Out-Null
    $hostBinary=Join-Path $hostTemp 'cloudos-core'
    $saved=@{GOOS=$env:GOOS;GOARCH=$env:GOARCH;CGO_ENABLED=$env:CGO_ENABLED;GOCACHE=$env:GOCACHE;GOMODCACHE=$env:GOMODCACHE}
    try {
      $env:GOOS='linux';$env:GOARCH=$goarch;$env:CGO_ENABLED='0';$env:GOCACHE=(Join-Path $hostTemp 'gocache');$env:GOMODCACHE=(Join-Path $hostTemp 'gomodcache')
      & $go.Source -C $sourceWindows build -trimpath -o $hostBinary ./cmd/cloudos-core
      if ($LASTEXITCODE -ne 0) { throw 'GO_BUILD_FAILED' }
    } finally { foreach($key in $saved.Keys){[Environment]::SetEnvironmentVariable($key,$saved[$key])} }
    $hostLinux = ConvertTo-CloudOSWslPath -WslExe $WslExe -Distribution $Distribution -WindowsPath $hostBinary
    [void](Invoke-CloudOSWsl -WslExe $WslExe -Arguments @('--distribution',$Distribution,'--exec','/bin/cp',$hostLinux,$linuxBinary))
    Remove-Item -LiteralPath $hostTemp -Recurse -Force -ErrorAction SilentlyContinue
    $built=$true
  }
  [void](Invoke-CloudOSWsl -WslExe $WslExe -Arguments @('--distribution',$Distribution,'--exec','/bin/chmod','700',$linuxBinary))
  [pscustomobject]@{ Path=$linuxBinary; GoCache=$goCache; ModCache=$modCache }
}

function Remove-CloudOSTemporaryCore {
  param([Parameter(Mandatory)][string]$WslExe,[Parameter(Mandatory)][string]$Distribution,[Parameter(Mandatory)]$Core)
  foreach ($path in @($Core.Path,$Core.GoCache,$Core.ModCache)) {
    if ([string]::IsNullOrWhiteSpace($path) -or $path -notmatch '^/tmp/cloudos-(?:core-visible-terminal|visible-go-cache|visible-go-mod)-[0-9a-f]{32}$') { continue }
    $flag = if ($path -eq $Core.Path) {'-f'} else {'-rf'}
    [void](Invoke-CloudOSWsl -WslExe $WslExe -Arguments @('--distribution',$Distribution,'--exec','/bin/rm',$flag,$path) -AllowFailure)
  }
}

function Get-CloudOSFreePort {
  $listener=[Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback,0)
  $listener.Start(); try { return ([Net.IPEndPoint]$listener.LocalEndpoint).Port } finally { $listener.Stop() }
}

function Start-CloudOSNodeProcess {
  param([Parameter(Mandatory)][string]$NodeExe,[Parameter(Mandatory)][string]$Script,[Parameter(Mandatory)][string]$WorkingDirectory,[Parameter(Mandatory)][hashtable]$Environment)
  $psi=[Diagnostics.ProcessStartInfo]::new()
  $psi.FileName=$NodeExe; $psi.UseShellExecute=$false; $psi.CreateNoWindow=$true; $psi.WorkingDirectory=$WorkingDirectory
  $psi.ArgumentList.Add($Script)
  foreach($entry in $Environment.GetEnumerator()){ $psi.Environment[$entry.Key]=[string]$entry.Value }
  return [Diagnostics.Process]::Start($psi)
}

function Wait-CloudOSJsonFile {
  param([Parameter(Mandatory)][string]$Path,[int]$TimeoutSeconds=25)
  $deadline=[DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
  while([DateTime]::UtcNow -lt $deadline){
    if(Test-Path -LiteralPath $Path){ try { return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json } catch {} }
    Start-Sleep -Milliseconds 150
  }
  throw "RUNTIME_FILE_TIMEOUT:$Path"
}

function Stop-CloudOSOwnedProcess {
  param($Process)
  if($null -eq $Process){return}
  try { if(-not $Process.HasExited){ Stop-Process -Id $Process.Id -Force -ErrorAction SilentlyContinue; $Process.WaitForExit(3000) | Out-Null } } catch {}
}

function Get-CloudOSPathFingerprint {
  param([Parameter(Mandatory)][string]$Path)
  if(-not (Test-Path -LiteralPath $Path)){return '__ABSENT__'}
  $rows = Get-ChildItem -LiteralPath $Path -Recurse -File -ErrorAction SilentlyContinue | Sort-Object FullName | ForEach-Object {
    $hash=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
    "{0}|{1}|{2}" -f $_.FullName.Substring($Path.Length),$_.Length,$hash
  }
  return [string]::Join("`n",$rows)
}
