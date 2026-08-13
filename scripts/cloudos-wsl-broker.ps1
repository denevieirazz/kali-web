param(
  [Parameter(Mandatory = $true)]
  [ValidateSet('Install', 'Update')]
  [string]$Action,

  [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]{0,79}$')]
  [string]$Distro,

  [switch]$WebDownload,

  [switch]$Elevated
)

$ErrorActionPreference = 'Stop'
$wslExecutable = Join-Path $env:WINDIR 'System32\wsl.exe'

if (-not (Test-Path -LiteralPath $wslExecutable)) {
  throw 'wsl.exe não foi encontrado neste Windows.'
}

function Test-CloudOSAdministrator {
  $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
  $principal = New-Object Security.Principal.WindowsPrincipal($identity)
  return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

$wslArguments = switch ($Action) {
  'Install' {
    if (-not $Distro) { throw 'A distribuição é obrigatória para instalação.' }
    $values = @('--install', '--distribution', $Distro, '--no-launch')
    if ($WebDownload) { $values += '--web-download' }
    $values
  }
  'Update' { @('--update') }
}

if ((Test-CloudOSAdministrator) -or $Elevated) {
  & $wslExecutable @wslArguments
  exit $LASTEXITCODE
}

$quotedScriptPath = '"' + $PSCommandPath + '"'
$forwarded = @('-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $quotedScriptPath, '-Action', $Action, '-Elevated')
if ($Distro) { $forwarded += @('-Distro', $Distro) }
if ($WebDownload) { $forwarded += '-WebDownload' }

Write-Output 'Aguardando confirmação administrativa do Windows...'
$process = Start-Process -FilePath 'powershell.exe' -ArgumentList $forwarded -Verb RunAs -WindowStyle Hidden -Wait -PassThru
exit $process.ExitCode
