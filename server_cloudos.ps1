# =====================================================================
# 🛡️ CloudOS Web Desktop Engine - Servidor HTTP Local (Porta 5173)
# Servidor nativo em PowerShell com Seed Data de Apps, Notificações e APIs.
# =====================================================================

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$distDir = Join-Path $scriptDir "cloudos-frontend\dist"

if (-not (Test-Path $distDir)) {
    $distDir = Join-Path $scriptDir "dist"
}

# Tentar portas em ordem (5173, 5174, 5175)
$port = 0
$listener = $null
foreach ($tryPort in @(5173, 5174, 5175)) {
    try {
        $testListener = New-Object System.Net.HttpListener
        $testListener.Prefixes.Add("http://localhost:${tryPort}/")
        $testListener.Start()
        $port = $tryPort
        $listener = $testListener
        break
    } catch {
        continue
    }
}

if ($null -eq $listener) {
    Write-Host "❌ Erro: Nenhuma porta livre para o CloudOS" -ForegroundColor Red
    exit 1
}

Write-Host "🛡️ CloudOS Web Desktop ativo em http://localhost:${port}/" -ForegroundColor Green

# Salvar a porta ativa
$activePortFile = Join-Path $scriptDir "cloudos_active_port.txt"
Set-Content -Path $activePortFile -Value $port -Encoding UTF8

function Get-CloudOS-Apps {
    return @(
        @{ id = "terminal"; app_id = "terminal"; name = "Terminal Pro"; icon = "terminal"; category = "system"; is_pinned = $true; description = "Terminal Kali Linux com suporte a multiplas abas" },
        @{ id = "files"; app_id = "files"; name = "Gerenciador de Arquivos"; icon = "files"; category = "system"; is_pinned = $true; description = "Gerencie arquivos no WSL2" },
        @{ id = "kalihub"; app_id = "kalihub"; name = "Kali Hub"; icon = "kalihub"; category = "security"; is_pinned = $true; description = "Central de ferramentas de pentest" },
        @{ id = "editor"; app_id = "editor"; name = "Editor de Codigo"; icon = "editor"; category = "development"; is_pinned = $false; description = "Editor Monaco com syntax highlighting" },
        @{ id = "settings"; app_id = "settings"; name = "Configuracoes"; icon = "settings"; category = "system"; is_pinned = $false; description = "Painel de controle do CloudOS" },
        @{ id = "toolrunner"; app_id = "toolrunner"; name = "Tool Runner"; icon = "toolrunner"; category = "security"; is_pinned = $true; description = "Executor visual de ferramentas Kali" },
        @{ id = "pipeline"; app_id = "pipeline"; name = "Pipeline Builder"; icon = "pipeline"; category = "automation"; is_pinned = $false; description = "Construtor de fluxos de automacao" },
        @{ id = "findings"; app_id = "findings"; name = "Findings Manager"; icon = "findings"; category = "security"; is_pinned = $false; description = "Gerenciador de vulnerabilidades" },
        @{ id = "evidence"; app_id = "evidence"; name = "Evidence Vault"; icon = "evidence"; category = "security"; is_pinned = $false; description = "Cofre seguro de evidencias" },
        @{ id = "report"; app_id = "report"; name = "Report Builder"; icon = "report"; category = "security"; is_pinned = $false; description = "Gerador de relatorios em Markdown" },
        @{ id = "projects"; app_id = "projects"; name = "Projetos"; icon = "projects"; category = "system"; is_pinned = $false; description = "Gerenciador de escopos de pentest" },
        @{ id = "snapshots"; app_id = "snapshots"; name = "Snapshots"; icon = "snapshots"; category = "system"; is_pinned = $false; description = "Gerenciador de backups do WSL" },
        @{ id = "missions"; app_id = "missions"; name = "Lab Missions"; icon = "missions"; category = "training"; is_pinned = $false; description = "Treinamento gamificado Red Team" },
        @{ id = "events"; app_id = "events"; name = "Central de Eventos"; icon = "events"; category = "system"; is_pinned = $false; description = "Logs e auditoria do sistema" },
        @{ id = "repeater"; app_id = "repeater"; name = "HTTP Repeater"; icon = "repeater"; category = "security"; is_pinned = $false; description = "Proxy de requisicoes HTTP" },
        @{ id = "doctor"; app_id = "doctor"; name = "Environment Doctor"; icon = "doctor"; category = "system"; is_pinned = $false; description = "Diagnostico do ambiente" }
    )
}

function Get-CloudOS-Notifications {
    return @(
        @{ id = "1"; type = "info"; title = "Bem-vindo ao CloudOS"; message = "Sistema operacional web pronto para uso"; created_at = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ"); read = $false },
        @{ id = "2"; type = "success"; title = "Servidor Nativo Ativo"; message = "CloudOS Desktop rodando na porta 5173"; created_at = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ"); read = $false }
    )
}

while ($listener.IsListening) {
    $context = $listener.GetContext()
    $req = $context.Request
    $res = $context.Response
    $urlPath = $req.Url.AbsolutePath

    # Cabeçalhos CORS Globais
    $res.AddHeader("Access-Control-Allow-Origin", "*")
    $res.AddHeader("Access-Control-Allow-Headers", "*")
    $res.AddHeader("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS")

    if ($req.HttpMethod -eq "OPTIONS") {
        $res.StatusCode = 200
        $res.Close()
        continue
    }

    # Helper para enviar JSON
    function Send-Json($obj, [switch]$IsArray) {
        $jsonStr = ""
        if ($null -ne $obj) {
            try {
                $jsonStr = $obj | ConvertTo-Json -Depth 5 -Compress
            } catch {
                $jsonStr = ""
            }
        }
        
        if ([string]::IsNullOrWhiteSpace($jsonStr)) {
            $jsonStr = if ($IsArray) { "[]" } else { "{}" }
        } else {
            if ($IsArray -and (-not $jsonStr.StartsWith("["))) {
                $jsonStr = "[$jsonStr]"
            }
        }

        $res.ContentType = "application/json; charset=utf-8"
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($jsonStr)
        $res.ContentLength64 = $bytes.Length
        if ($req.HttpMethod -ne "HEAD") {
            $res.OutputStream.Write($bytes, 0, $bytes.Length)
        }
        $res.Close()
    }

    # --- ROTAS API NATIVAS CLOUDOS & TELEMETRIA DRONE ---

    if ($urlPath -eq "/api/drone/log" -and $req.HttpMethod -eq "POST") {
        try {
            $reader = New-Object System.IO.StreamReader($req.InputStream, $req.ContentEncoding)
            $droneBody = $reader.ReadToEnd()
            $droneLogFile = Join-Path $scriptDir "cloudos_drone_errors.log"
            [System.IO.File]::AppendAllText($droneLogFile, $droneBody + "`n", [System.Text.Encoding]::UTF8)
        } catch {}
        Send-Json @{ status="logged"; drone="active" }
        continue
    }

    if ($urlPath -eq "/api/health") {
        Send-Json @{ status="ok"; system="CloudOS Enterprise"; wslReady=$false; wslNeedEnable=$true }
        continue
    }

    if ($urlPath -eq "/api/auth/login") {
        Send-Json @{ token="cloudos_jwt_token_operator"; status="ok"; username="admin"; message="Autenticado" }
        continue
    }

    if ($urlPath -eq "/api/user/state") {
        Send-Json @{ username="operator"; role="administrator"; authenticated=$true; preferences=@{} }
        continue
    }

    if ($urlPath -eq "/api/apps" -or $urlPath -eq "/api/apps/toggle") {
        Send-Json (Get-CloudOS-Apps) -IsArray
        continue
    }

    if ($urlPath -eq "/api/notifications") {
        Send-Json (Get-CloudOS-Notifications) -IsArray
        continue
    }

    if ($urlPath -eq "/api/system/status") {
        Send-Json @{
            status = "ok"
            cpu = 12
            memory = 35
            uptime = 7200
            wsl = "Requer Ativacao do WSL2 no Windows"
            torActive = $true
            currentMac = "00:1A:2B:3C:4D:5E"
            diskUsage = "18.4 GB / 100 GB (18%)"
            activeSessions = 1
            recentErrors = @()
            processes = @()
            network = @()
        }
        continue
    }

    if ($urlPath -eq "/api/kali/tools" -or $urlPath -eq "/api/kali/tools/status") {
        Send-Json @(
            @{ id="nmap"; name="Nmap"; category="Reconnaissance"; description="Network Mapper and Port Scanner"; status="installed" },
            @{ id="sqlmap"; name="SQLMap"; category="Exploitation"; description="Automatic SQL Injection Tool"; status="installed" },
            @{ id="gobuster"; name="Gobuster"; category="Web Recon"; description="Directory/File & DNS Busting Tool"; status="installed" },
            @{ id="hydra"; name="Hydra"; category="Brute Force"; description="Network Login Cracker"; status="installed" },
            @{ id="nuclei"; name="Nuclei"; category="Vulnerability Scanner"; description="Fast Template-based Vulnerability Scanner"; status="installed" }
        ) -IsArray
        continue
    }

    if ($urlPath -eq "/api/kali/tools/favorites") {
        Send-Json @("nmap", "gobuster", "sqlmap", "nuclei") -IsArray
        continue
    }

    if ($urlPath -eq "/api/projects") {
        Send-Json @(
            @{ id=1; name="Default Pentest Scope"; target="127.0.0.1"; status="active"; createdAt="2026-08-02" }
        ) -IsArray
        continue
    }

    if ($urlPath -eq "/api/snapshots") {
        Send-Json @(
            @{ id=1; name="Clean Baseline"; createdAt="2026-08-02"; size="1.2 GB" }
        ) -IsArray
        continue
    }

    if ($urlPath -eq "/api/events") {
        Send-Json @(
            @{ id=1; type="system"; message="CloudOS Subsystem Initialized"; timestamp="2026-08-02 20:00:00" }
        ) -IsArray
        continue
    }

    if ($urlPath -eq "/api/files") {
        Send-Json @(
            @{ name="root"; isDir=$true },
            @{ name="report_draft.md"; isDir=$false; size=1024 }
        ) -IsArray
        continue
    }

    if ($urlPath -eq "/api/v3/doctor") {
        Send-Json @(
            @{ name="WSL2 Kali Linux Subsystem"; status="warning"; detail="Requer comando: wsl --install" },
            @{ name="SQLite WAL Database Storage"; status="ok"; detail="Banco de dados ativo" },
            @{ name="Dockerode Execution Proxy"; status="ok"; detail="Proxy pronto" },
            @{ name="Terminal Manager (PowerShell Engine)"; status="ok"; detail="Terminal pronto" }
        ) -IsArray
        continue
    }

    # Catch-All Wildcard para QUALQUER Rota API (/api/*) - RETORNA ARRAY VAZIO GUARANTIDO ([])
    if ($urlPath.StartsWith("/api/")) {
        Send-Json @() -IsArray
        continue
    }

    # --- SERVIR ARQUIVOS ESTÁTICOS / SPA FALLBACK ---

    $cleanPath = $urlPath.TrimStart('/')
    if ([string]::IsNullOrWhiteSpace($cleanPath)) {
        $targetFile = Join-Path $distDir "index.html"
    } else {
        $cleanPath = $cleanPath.Replace('/', '\')
        $targetFile = Join-Path $distDir $cleanPath
    }

    if (-not (Test-Path -Path $targetFile -PathType Leaf)) {
        $targetFile = Join-Path $distDir "index.html"
    }

    if (Test-Path -Path $targetFile -PathType Leaf) {
        $ext = [System.IO.Path]::GetExtension($targetFile).ToLower()
        $contentType = switch ($ext) {
            ".html" { "text/html; charset=utf-8" }
            ".js"   { "application/javascript; charset=utf-8" }
            ".mjs"  { "application/javascript; charset=utf-8" }
            ".css"  { "text/css; charset=utf-8" }
            ".svg"  { "image/svg+xml" }
            ".ico"  { "image/x-icon" }
            ".png"  { "image/png" }
            ".jpg"  { "image/jpeg" }
            ".json" { "application/json; charset=utf-8" }
            ".woff2"{ "font/woff2" }
            Default { "application/octet-stream" }
        }

        try {
            $bytes = [System.IO.File]::ReadAllBytes($targetFile)
            $res.ContentType = $contentType
            $res.ContentLength64 = $bytes.Length
            if ($req.HttpMethod -ne "HEAD") {
                $res.OutputStream.Write($bytes, 0, $bytes.Length)
            }
        } catch {
            $res.StatusCode = 500
        }
    } else {
        $res.StatusCode = 404
    }
    $res.Close()
}
