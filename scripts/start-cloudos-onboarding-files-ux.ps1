[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$node = (Get-Command node -ErrorAction Stop).Source
$runId = [Guid]::NewGuid().ToString('N')
$temp = Join-Path ([IO.Path]::GetTempPath()) "cloudos-onboarding-files-ux-$runId"
$runtime = Join-Path $temp 'runtime'
$data = Join-Path $temp 'data'
$backend = $null
$frontend = $null
New-Item -ItemType Directory -Force -Path $runtime,$data | Out-Null

function Get-FreePort {
  $listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback,0)
  $listener.Start()
  try { return ([Net.IPEndPoint]$listener.LocalEndpoint).Port } finally { $listener.Stop() }
}

function Start-NodeChild {
  param([string]$Script,[string]$WorkingDirectory,[hashtable]$Environment)
  $psi = [Diagnostics.ProcessStartInfo]::new()
  $psi.FileName = $node
  $psi.UseShellExecute = $false
  $psi.CreateNoWindow = $true
  $psi.WorkingDirectory = $WorkingDirectory
  $psi.ArgumentList.Add($Script)
  foreach ($entry in $Environment.GetEnumerator()) { $psi.Environment[$entry.Key] = [string]$entry.Value }
  return [Diagnostics.Process]::Start($psi)
}

function Wait-JsonFile {
  param([string]$Path,[int]$TimeoutSeconds=25)
  $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
  while ([DateTime]::UtcNow -lt $deadline) {
    if (Test-Path -LiteralPath $Path) {
      try { return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json } catch {}
    }
    Start-Sleep -Milliseconds 150
  }
  throw "RUNTIME_FILE_TIMEOUT:$Path"
}

function Stop-OwnedProcess {
  param($Process)
  if ($null -eq $Process) { return }
  try {
    if (-not $Process.HasExited) {
      Stop-Process -Id $Process.Id -Force -ErrorAction SilentlyContinue
      [void]$Process.WaitForExit(3000)
    }
  } catch {}
}

try {
  $frontPort = Get-FreePort
  $environment = @{
    NODE_ENV = 'development'
    PORT = '0'
    HOST = '127.0.0.1'
    CLOUDOS_RUNTIME_DIR = $runtime
    CLOUDOS_DATA_DIR = $data
    DATABASE_PATH = (Join-Path $data 'cloudos.json')
    CLOUDOS_FRONTEND_PORT = [string]$frontPort
    CLOUDOS_FRONTEND_STRICT_PORT = '1'
    CORS_ORIGIN = "http://127.0.0.1:$frontPort"
    JWT_SECRET = "cloudos-onboarding-files-ux-$runId"
    CLOUDOS_NATIVE_HOST = '0'
    CLOUDOS_SUPERVISOR_TOKEN = ''
    CLOUDOS_HOST_LEASE_PIPE = ''
    CLOUDOS_HOST_LEASE_TOKEN = ''
    CLOUDOS_RUN_ID = ''
    CLOUDOS_PARENT_PID = ''
    CLOUDOS_WSL_CORE_FOUNDATION = '0'
    CLOUDOS_WSL_CORE_FILES = '0'
    CLOUDOS_WSL_CORE_TERMINAL = '0'
    CLOUDOS_WSL_CORE_TERMINAL_FALLBACK = '0'
  }

  $backend = Start-NodeChild -Script (Join-Path $root 'backend\src\server.js') -WorkingDirectory (Join-Path $root 'backend') -Environment $environment
  [void](Wait-JsonFile -Path (Join-Path $runtime 'backend-port.json'))
  $frontend = Start-NodeChild -Script (Join-Path $root 'frontend\scripts\dev-server.js') -WorkingDirectory (Join-Path $root 'frontend') -Environment $environment
  $frontRuntime = Wait-JsonFile -Path (Join-Path $runtime 'frontend-port.json')

  Write-Host ''
  Write-Host 'CloudOS — revisão Onboarding + Files UX' -ForegroundColor Cyan
  Write-Host 'Banco/runtime: temporários e isolados' -ForegroundColor Green
  Write-Host 'WSL Core / Browser / Terminal / System Center: não alterados nem iniciados por este launcher' -ForegroundColor Green
  Write-Host ''
  Write-Host 'Checklist físico/visual:' -ForegroundColor Yellow
  Write-Host '  1. OOBE em 1366x768: percorra tudo com Tab; nada pode deslocar ou cortar.'
  Write-Host '  2. Teste zoom do navegador em 100%, 125% e 150%, depois estreite a janela.'
  Write-Host '  3. Crie a conta com senha de exatamente 4 caracteres e depois teste uma frase-senha com espaços.'
  Write-Host '  4. No recovery: Copiar, Salvar .txt escolhendo destino e Imprimir.'
  Write-Host '  5. Use Esqueci minha senha e carregue o .txt salvo; confirme que o código antigo não reutiliza.'
  Write-Host '  6. No CloudOS Files: envie imagens/JSON/PDF/Markdown/código/zip, alterne Grade/Lista e observe miniaturas.'
  Write-Host '  7. Imagem acima de 8 MiB deve ficar com ícone, sem miniatura pesada.'
  Write-Host ''
  Write-Host 'Pressione Ctrl+C aqui para encerrar somente esta sessão.' -ForegroundColor Yellow
  Start-Process $frontRuntime.url

  while ($true) {
    Start-Sleep -Seconds 1
    if ($backend.HasExited -or $frontend.HasExited) { throw 'DEV_PROCESS_EXITED' }
  }
} finally {
  Stop-OwnedProcess $frontend
  Stop-OwnedProcess $backend
  Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
}
