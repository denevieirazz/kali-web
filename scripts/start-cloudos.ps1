param(
  [string]$Distro = 'kali-linux',
  [ValidateSet('Web','Full')]
  [string]$Mode = 'Full',
  [switch]$AllowOffline
)

Set-StrictMode -Version Latest

$root = Split-Path -Parent $PSScriptRoot
if ($Mode -eq 'Web') {
    $cmd = 'cmd'
    $cmdArgs = @('/c', 'npm.cmd', 'run', 'dev')
    try {
        Start-Process -FilePath $cmd -ArgumentList $cmdArgs -WorkingDirectory $root -WindowStyle Hidden
        Write-Host 'CloudOS Web iniciado.'
    } catch {
        Write-Verbose $_.Exception.Message
        Write-Error 'Não foi possível iniciar o CloudOS Web. Verifique o ambiente de desenvolvimento e tente novamente.'
        exit 1
    }
    exit 0
}

$runner = Join-Path $PSScriptRoot 'run-native-host.ps1'
try {
    & $runner -Distro $Distro -AllowOffline:$AllowOffline
    exit 0
} catch {
    Write-Verbose $_.Exception.Message
    Write-Error 'Não foi possível iniciar o CloudOS em modo Full. Execute os diagnósticos para obter detalhes antes de tentar novamente.'
    exit 1
}
