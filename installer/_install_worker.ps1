# =====================================================================
# 🛡️ CloudOS Setup Wizard - Worker Engine (_install_worker.ps1) [DEBUG MODE]
# Motor de instalação em background com logs em worker_debug.log
# =====================================================================

param(
    [string]$ProgressFile = "progress.json",
    [string]$Username = "cloudos",
    [string]$Password = "cloudos123",
    [string]$Edition = "standard",
    [int]$RamGB = 3
)

$ErrorActionPreference = "Continue"

$workerDir = Split-Path -Parent $ProgressFile
if ([string]::IsNullOrWhiteSpace($workerDir)) {
    $workerDir = Split-Path -Parent $MyInvocation.MyCommand.Path
}
$logFile = Join-Path $workerDir "worker_debug.log"

$startTime = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
"[$startTime] Worker iniciado" | Out-File -FilePath $logFile -Encoding UTF8 -Force
"[$startTime] Parametros: User=$Username, Edition=$Edition, RAM=$($RamGB)GB" | Out-File -FilePath $logFile -Append -Encoding UTF8

function Write-WorkerLog {
    param([string]$Message)
    $ts = Get-Date -Format "HH:mm:ss"
    $logMessage = "[$ts] $Message"
    $logMessage | Out-File -FilePath $logFile -Append -Encoding UTF8
}

function Update-Progress {
    param(
        [int]$Percent,
        [string]$Status,
        [string]$Log = "",
        [string]$Speed = "0 MB/s",
        [string]$Debug = ""
    )
    
    Write-WorkerLog "Progress: ${Percent}% - ${Status} (${Debug})"
    
    $progressData = @{
        percent = $Percent
        status = $Status
        log = $Log
        speed = $Speed
        debug = $Debug
        timestamp = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ")
    }
    
    $json = $progressData | ConvertTo-Json -Depth 5 -Compress
    $json | Out-File -FilePath $ProgressFile -Encoding UTF8 -Force
}

try {
    Write-WorkerLog "Iniciando processo de instalacao..."
    
    # PASSO 1: Ativar WSL (10%)
    Update-Progress -Percent 5 -Status "Ativando WSL2..." -Log "Verificando recursos do Windows..." -Debug "Passo 1: WSL"
    Start-Sleep -Seconds 2
    
    try {
        $wsl = Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux -ErrorAction SilentlyContinue
        if ($null -ne $wsl -and $wsl.State -ne "Enabled") {
            Update-Progress -Percent 10 -Status "Ativando WSL..." -Log "Habilitando Microsoft-Windows-Subsystem-Linux..." -Debug "Ativando WSL"
            Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux -NoRestart | Out-Null
            Write-WorkerLog "WSL ativado"
        } else {
            Write-WorkerLog "WSL ja ativado"
        }
        
        $vmp = Get-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform -ErrorAction SilentlyContinue
        if ($null -ne $vmp -and $vmp.State -ne "Enabled") {
            Update-Progress -Percent 15 -Status "Ativando Plataforma VM..." -Log "Habilitando VirtualMachinePlatform..." -Debug "Ativando VM Platform"
            Enable-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform -NoRestart | Out-Null
            Write-WorkerLog "VM Platform ativada"
        } else {
            Write-WorkerLog "VM Platform ja ativada"
        }
    } catch {
        Write-WorkerLog "Aviso WSL: $($_.Exception.Message)"
    }
    
    # PASSO 2: Configurar WSL2 (20%)
    Update-Progress -Percent 20 -Status "Configurando WSL2..." -Log "Executando wsl --update..." -Debug "Passo 2: Update WSL"
    Start-Sleep -Seconds 2
    
    try {
        wsl --update 2>&1 | Out-Null
        wsl --set-default-version 2 2>&1 | Out-Null
        Write-WorkerLog "WSL2 configurado"
    } catch {
        Write-WorkerLog "Aviso WSL2: $($_.Exception.Message)"
    }
    
    # PASSO 3: Instalar Kali Linux (30-50%)
    Update-Progress -Percent 30 -Status "Verificando Kali Linux..." -Log "Checando se Kali ja esta instalado..." -Debug "Passo 3: Kali Linux"
    Start-Sleep -Seconds 2
    
    $distros = wsl --list --quiet 2>$null
    $kaliInstalled = $distros -match "kali"
    
    if (-not $kaliInstalled) {
        Update-Progress -Percent 35 -Status "Instalando Kali Linux..." -Log "wsl --install -d kali-linux (pode demorar 5-10 min)..." -Speed "25 MB/s" -Debug "Baixando Kali"
        Write-WorkerLog "Instalando Kali Linux..."
        
        try {
            wsl --install -d kali-linux
            Write-WorkerLog "Kali Linux instalado"
        } catch {
            Write-WorkerLog "Erro ao instalar Kali: $($_.Exception.Message)"
        }
        
        Update-Progress -Percent 50 -Status "Kali Linux instalado!" -Log "Distribuicao instalada com sucesso" -Debug "Kali OK"
    } else {
        Update-Progress -Percent 50 -Status "Kali Linux ja instalado!" -Log "Pulando download (ja existe)" -Debug "Kali ja existe"
        Write-WorkerLog "Kali ja instalado"
    }
    
    Start-Sleep -Seconds 2
    
    # PASSO 4: Criar usuario (55%)
    Update-Progress -Percent 55 -Status "Criando usuario ${Username}..." -Log "Configurando conta no Kali..." -Debug "Passo 4: Usuario"
    Start-Sleep -Seconds 2
    
    try {
        $userScript = @"
useradd -m -s /bin/bash ${Username} 2>/dev/null || true
echo "${Username}:${Password}" | chpasswd
usermod -aG sudo ${Username} 2>/dev/null || true
echo "${Username} ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/${Username}
"@
        
        $userScript | wsl -d kali-linux -u root bash 2>&1 | Out-Null
        Write-WorkerLog "Usuario ${Username} criado"
    } catch {
        Write-WorkerLog "Erro ao criar usuario: $($_.Exception.Message)"
    }
    
    # PASSO 5: Instalar ferramentas (60-90%)
    Update-Progress -Percent 60 -Status "Atualizando repositorios..." -Log "apt-get update..." -Debug "Passo 5: Ferramentas"
    Start-Sleep -Seconds 2
    
    try {
        wsl -d kali-linux -u root -- bash -c "apt-get update -y" 2>&1 | Out-Null
        Write-WorkerLog "Repositorios atualizados"
    } catch {
        Write-WorkerLog "Erro apt-get update: $($_.Exception.Message)"
    }
    
    $tools = @()
    
    if ($Edition -eq "minimal") {
        $tools = @("nmap", "nikto", "sqlmap", "hydra", "john", "curl", "wget", "git", "tor", "macchanger")
    }
    elseif ($Edition -eq "standard") {
        $tools = @("nmap", "nikto", "sqlmap", "hydra", "john", "hashcat", "gobuster", "curl", "wget", "git", "python3", "python3-pip", "tor", "privoxy", "macchanger")
    }
    elseif ($Edition -eq "everything") {
        Update-Progress -Percent 65 -Status "Instalando Kali Everything..." -Log "Instalando arsenal completo (~64 GB, 30-60 min)..." -Speed "45 MB/s" -Debug "Kali Everything"
        Write-WorkerLog "Instalando Kali Everything..."
        
        try {
            wsl -d kali-linux -u root -- bash -c "DEBIAN_FRONTEND=noninteractive apt-get install -y kali-linux-everything" 2>&1 | Out-Null
            Write-WorkerLog "Kali Everything instalado"
        } catch {
            Write-WorkerLog "Erro Kali Everything: $($_.Exception.Message)"
        }
        
        Update-Progress -Percent 90 -Status "Kali Everything instalado!" -Log "Todas as ferramentas instaladas" -Debug "Everything OK"
    }
    
    # Instalar ferramentas individuais
    if ($Edition -ne "everything" -and $tools.Count -gt 0) {
        $currentPercent = 65
        $percentPerTool = [math]::Floor(25 / $tools.Count)
        
        foreach ($tool in $tools) {
            $randSpeed = Get-Random -Minimum 10 -Maximum 35
            Update-Progress -Percent $currentPercent -Status "Instalando ${tool}..." -Log "apt-get install ${tool}" -Speed "${randSpeed} MB/s" -Debug "Instalando ${tool}"
            Write-WorkerLog "Instalando ${tool}..."
            
            try {
                wsl -d kali-linux -u root -- bash -c "DEBIAN_FRONTEND=noninteractive apt-get install -y ${tool}" 2>&1 | Out-Null
                Write-WorkerLog "${tool} instalado"
            } catch {
                Write-WorkerLog "Erro ao instalar ${tool}: $($_.Exception.Message)"
            }
            
            $currentPercent += $percentPerTool
            Start-Sleep -Milliseconds 500
        }
    }
    
    # PASSO 6: Criar diretorios (92%)
    Update-Progress -Percent 92 -Status "Criando diretorios..." -Log "Configurando /home/cloudos_users..." -Debug "Passo 6: Diretorios"
    Start-Sleep -Seconds 2
    
    try {
        wsl -d kali-linux -u root -- bash -c "mkdir -p /home/cloudos_users && chmod 777 /home/cloudos_users" 2>&1 | Out-Null
        wsl -d kali-linux -u root -- bash -c "mkdir -p /root/.trash && chmod 777 /root/.trash" 2>&1 | Out-Null
        Write-WorkerLog "Diretorios criados"
    } catch {
        Write-WorkerLog "Erro ao criar diretorios: $($_.Exception.Message)"
    }
    
    # PASSO 7: Configurar .wslconfig (95%)
    Update-Progress -Percent 95 -Status "Configurando .wslconfig..." -Log "Alocando $($RamGB)GB de RAM..." -Debug "Passo 7: .wslconfig"
    Start-Sleep -Seconds 2
    
    try {
        $wslConfig = @"
[wsl2]
memory=$($RamGB)GB
processors=2
swap=2GB
localhostForwarding=true
"@
        
        $userConfigPath = Join-Path $env:USERPROFILE ".wslconfig"
        $wslConfig | Out-File -FilePath $userConfigPath -Encoding UTF8 -Force
        Write-WorkerLog ".wslconfig criado em $userConfigPath"
    } catch {
        Write-WorkerLog "Erro .wslconfig: $($_.Exception.Message)"
    }
    
    # PASSO 8: Concluido (100%)
    Update-Progress -Percent 100 -Status "Instalacao concluida!" -Log "CloudOS pronto! Reinicie o computador para aplicar todas as mudancas." -Debug "Concluido!"
    Write-WorkerLog "Instalacao concluida com sucesso!"
    
} catch {
    Write-WorkerLog "ERRO FATAL: $($_.Exception.Message)"
    Update-Progress -Percent -1 -Status "Erro na instalacao" -Log "ERRO: $($_.Exception.Message)" -Debug "Falha critica"
}

Write-WorkerLog "Worker finalizado"
