# =====================================================================
# 🛡️ CloudOS Setup Wizard - Server Engine (server_installer.ps1) [DEBUG MODE]
# Servidor HTTP local do Instalador Web com Telemetria e Logs em Disco
# =====================================================================

$ErrorActionPreference = "Continue"
$Host.UI.RawUI.WindowTitle = "CloudOS Installer Server (DEBUG)"

function Get-FreePort {
    param([int]$StartPort = 9999)
    for ($p = $StartPort; $p -lt ($StartPort + 10); $p++) {
        try {
            $testListener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, $p)
            $testListener.Start()
            $testListener.Stop()
            return $p
        } catch {
            continue
        }
    }
    return $StartPort
}

$port = Get-FreePort -StartPort 9999
$installerPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$progressFile = Join-Path $installerPath "progress.json"
$logFile = Join-Path $installerPath "installer_debug.log"

# Inicializar log em disco
$startTime = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
"[$startTime] Servidor iniciado na porta $port" | Out-File -FilePath $logFile -Encoding UTF8 -Force
"[$startTime] Caminho do instalador: $installerPath" | Out-File -FilePath $logFile -Append -Encoding UTF8

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  CloudOS Installer Server (DEBUG)" -ForegroundColor Cyan
Write-Host "  Porta: $port" -ForegroundColor Cyan
Write-Host "  Log: $logFile" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Salvar porta ativa
$port | Out-File -FilePath (Join-Path $installerPath "active_port.txt") -Encoding UTF8 -Force

# Abrir navegador automaticamente apos 1.5s
try {
    Start-Sleep -Milliseconds 1500
    Start-Process "http://localhost:$port"
} catch {}

# Inicializar progress.json
@{
    percent = 0
    status = "Aguardando instalacao..."
    log = "Servidor pronto para receber requisicoes"
    speed = "0 MB/s"
    debug = "Servidor iniciado com sucesso"
    timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ")
} | ConvertTo-Json | Out-File -FilePath $progressFile -Encoding UTF8 -Force

Write-Host "Arquivo progress.json criado com sucesso." -ForegroundColor Green
Write-Host ""

# Criar listener HTTP
$listener = [System.Net.HttpListener]::new()
$listener.Prefixes.Add("http://localhost:${port}/")
$listener.Start()

Write-Host "Servidor HTTP iniciado. Aguardando requisicoes em http://localhost:${port}" -ForegroundColor Green
Write-Host ""

function Write-Log {
    param([string]$Message, [string]$Color = "White")
    $ts = Get-Date -Format "HH:mm:ss"
    $logMessage = "[$ts] $Message"
    Write-Host $logMessage -ForegroundColor $Color
    $logMessage | Out-File -FilePath $logFile -Append -Encoding UTF8
}

function Send-JsonResponse {
    param($Response, $Data, [int]$StatusCode = 200)
    
    $json = $Data | ConvertTo-Json -Depth 10 -Compress
    $buffer = [System.Text.Encoding]::UTF8.GetBytes($json)
    
    $Response.StatusCode = $StatusCode
    $Response.ContentType = "application/json; charset=utf-8"
    $Response.Headers.Add("Access-Control-Allow-Origin", "*")
    $Response.Headers.Add("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
    $Response.Headers.Add("Access-Control-Allow-Headers", "Content-Type")
    $Response.ContentLength64 = $buffer.Length
    $Response.OutputStream.Write($buffer, 0, $buffer.Length)
    $Response.Close()
}

function Send-FileResponse {
    param($Response, $FilePath, $ContentType)
    
    if (Test-Path $FilePath) {
        $bytes = [System.IO.File]::ReadAllBytes($FilePath)
        $Response.StatusCode = 200
        $Response.ContentType = $ContentType
        $Response.Headers.Add("Access-Control-Allow-Origin", "*")
        $Response.ContentLength64 = $bytes.Length
        $Response.OutputStream.Write($bytes, 0, $bytes.Length)
    } else {
        $Response.StatusCode = 404
        Write-Log "Arquivo nao encontrado: $FilePath" "Red"
    }
    $Response.Close()
}

while ($listener.IsListening) {
    $context = $listener.GetContext()
    $request = $context.Request
    $response = $context.Response
    $path = $request.Url.LocalPath
    $method = $request.HttpMethod
    
    Write-Log "[$method] $path" "Gray"
    
    try {
        # CORS Preflight
        if ($method -eq "OPTIONS") {
            $response.StatusCode = 200
            $response.Headers.Add("Access-Control-Allow-Origin", "*")
            $response.Headers.Add("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
            $response.Headers.Add("Access-Control-Allow-Headers", "Content-Type")
            $response.Close()
            continue
        }
        
        if ($path -eq "/" -or $path -eq "/index.html") {
            Send-FileResponse -Response $response -FilePath (Join-Path $installerPath "index.html") -ContentType "text/html; charset=utf-8"
            continue
        }
        
        if ($path -eq "/installer.css") {
            Send-FileResponse -Response $response -FilePath (Join-Path $installerPath "installer.css") -ContentType "text/css; charset=utf-8"
            continue
        }
        
        if ($path -eq "/installer.js") {
            Send-FileResponse -Response $response -FilePath (Join-Path $installerPath "installer.js") -ContentType "application/javascript; charset=utf-8"
            continue
        }
        
        if ($path -eq "/api/diagnostics" -or $path -eq "/api/system-info") {
            Write-Log "Diagnostico solicitado pelo frontend" "Cyan"
            
            $diag = @{
                ramTotalGB = [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB, 1)
                cpuCores = (Get-CimInstance Win32_Processor).NumberOfCores
                diskFreeGB = [math]::Round((Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'").FreeSpace / 1GB, 1)
                wslEnabled = $false
                virtualizationEnabled = $true
            }
            
            try {
                $wsl = Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux -ErrorAction SilentlyContinue
                if ($null -ne $wsl -and $wsl.State -eq "Enabled") {
                    $diag.wslEnabled = $true
                }
            } catch {
                Write-Log "Erro ao checar WSL: $($_.Exception.Message)" "Yellow"
            }
            
            Write-Log "Diagnostico: RAM=$($diag.ramTotalGB)GB, CPU=$($diag.cpuCores), Disk=$($diag.diskFreeGB)GB, WSL=$($diag.wslEnabled)" "Green"
            Send-JsonResponse -Response $response -Data $diag
            continue
        }
        
        if ($path -eq "/api/install") {
            if ($method -eq "POST") {
                Write-Log "Requisicao de instalacao recebida!" "Yellow"
                
                $reader = [System.IO.StreamReader]::new($request.InputStream, $request.ContentEncoding)
                $rawBody = $reader.ReadToEnd()
                Write-Log "Body: $rawBody" "Cyan"
                
                $params = $rawBody | ConvertFrom-Json
                
                $username = if ($params.username) { $params.username } else { "cloudos" }
                $password = if ($params.password) { $params.password } else { "cloudos123" }
                $edition = if ($params.edition) { $params.edition } else { "standard" }
                $ramGB = if ($params.ramGB) { $params.ramGB } else { 3 }
                
                Write-Log "Parametros: user=$username, edition=$edition, ram=$($ramGB)GB" "Green"
                
                $workerPath = Join-Path $installerPath "_install_worker.ps1"
                if (Test-Path $workerPath) {
                    Write-Log "Worker encontrado em: $workerPath" "Green"
                    
                    $workerCmd = "& '$workerPath' -ProgressFile '$progressFile' -Username '$username' -Password '$password' -Edition '$edition' -RamGB $ramGB"
                    Write-Log "Disparando worker com comando: $workerCmd" "Yellow"
                    
                    try {
                        Start-Process powershell -ArgumentList "-NoProfile", "-ExecutionPolicy", "Bypass", "-WindowStyle", "Hidden", "-Command", $workerCmd -PassThru
                        Write-Log "Worker disparado com sucesso em segundo plano!" "Green"
                        
                        @{
                            percent = 1
                            status = "Instalacao iniciada..."
                            log = "Worker disparado em background"
                            speed = "0 MB/s"
                            debug = "Processo worker iniciado"
                            timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ")
                        } | ConvertTo-Json | Out-File -FilePath $progressFile -Encoding UTF8 -Force
                        
                        Send-JsonResponse -Response $response -Data @{ status = "started"; message = "Instalacao iniciada com sucesso" }
                    } catch {
                        Write-Log "ERRO ao disparar worker: $($_.Exception.Message)" "Red"
                        Send-JsonResponse -Response $response -Data @{ status = "error"; message = $_.Exception.Message } -StatusCode 500
                    }
                } else {
                    Write-Log "ERRO: Worker nao encontrado em $workerPath" "Red"
                    Send-JsonResponse -Response $response -Data @{ status = "error"; message = "Worker nao encontrado" } -StatusCode 500
                }
            } else {
                $response.StatusCode = 405
                $response.Close()
            }
            continue
        }
        
        if ($path -eq "/api/progress") {
            if (Test-Path $progressFile) {
                $rawProgress = Get-Content -Path $progressFile -Raw
                $progressData = $rawProgress | ConvertFrom-Json
                Send-JsonResponse -Response $response -Data $progressData
            } else {
                Send-JsonResponse -Response $response -Data @{ 
                    percent = 0
                    status = "Aguardando..."
                    log = "Arquivo progress.json nao encontrado"
                    speed = "0 MB/s"
                    debug = "Arquivo de progresso nao existe"
                }
            }
            continue
        }
        
        if ($path -eq "/api/debug") {
            $lastLogs = @()
            if (Test-Path $logFile) {
                $lastLogs = Get-Content $logFile -Tail 20
            }
            
            $debugData = @{
                serverRunning = $true
                port = $port
                installerPath = $installerPath
                progressFileExists = (Test-Path $progressFile)
                workerExists = (Test-Path (Join-Path $installerPath "_install_worker.ps1"))
                logFile = $logFile
                lastLogs = $lastLogs
            }
            Send-JsonResponse -Response $response -Data $debugData
            continue
        }
        
        $response.StatusCode = 404
        $response.Close()
        
    } catch {
        Write-Log "ERRO: $($_.Exception.Message)" "Red"
        $response.StatusCode = 500
        $response.Close()
    }
}
