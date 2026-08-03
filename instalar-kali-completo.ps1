#Requires -RunAsAdministrator
# =====================================================================
# 🛡️ CloudOS - Instalador Completo do WSL2 + Kali Linux + Ferramentas
# =====================================================================

$ErrorActionPreference = "Continue"
$Host.UI.RawUI.WindowTitle = "CloudOS Installer - WSL2 + Kali Linux"

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  CloudOS - Instalador Completo" -ForegroundColor Cyan
Write-Host "  WSL2 + Kali Linux + Ferramentas" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

function Write-Log {
    param([string]$Message, [string]$Color = "White")
    $timestamp = Get-Date -Format "HH:mm:ss"
    Write-Host "[$timestamp] " -ForegroundColor Gray -NoNewline
    Write-Host $Message -ForegroundColor $Color
}

# Verificar se esta rodando como Administrador
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Log "ERRO: Execute como Administrador!" "Red"
    pause
    exit 1
}

Write-Log "Permissoes de Administrador OK" "Green"
Write-Host ""

# PASSO 1: Ativar recursos do Windows
Write-Host "----------------------------------------" -ForegroundColor Yellow
Write-Log "PASSO 1/5: Ativando recursos do Windows..." "Yellow"
Write-Host "----------------------------------------" -ForegroundColor Yellow

try {
    $wsl = Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux -ErrorAction SilentlyContinue
    if ($wsl.State -ne "Enabled") {
        Write-Log "Ativando WSL..." "Cyan"
        Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Windows-Subsystem-Linux -NoRestart | Out-Null
        Write-Log "WSL ativado!" "Green"
    } else {
        Write-Log "WSL ja ativado" "Green"
    }

    $vmp = Get-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform -ErrorAction SilentlyContinue
    if ($vmp.State -ne "Enabled") {
        Write-Log "Ativando Plataforma de Maquina Virtual..." "Cyan"
        Enable-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform -NoRestart | Out-Null
        Write-Log "Plataforma VM ativada!" "Green"
    } else {
        Write-Log "Plataforma VM ja ativada" "Green"
    }
} catch {
    Write-Log "Aviso: $($_.Exception.Message)" "Yellow"
}

Write-Host ""

# PASSO 2: Configurar WSL2
Write-Host "----------------------------------------" -ForegroundColor Yellow
Write-Log "PASSO 2/5: Configurando WSL2..." "Yellow"
Write-Host "----------------------------------------" -ForegroundColor Yellow

Write-Log "Atualizando WSL..." "Cyan"
try {
    wsl --update
    wsl --set-default-version 2
    Write-Log "WSL2 configurado!" "Green"
} catch {
    Write-Log "WSL update aviso: $($_.Exception.Message)" "Yellow"
}

Write-Host ""

# PASSO 3: Instalar Kali Linux
Write-Host "----------------------------------------" -ForegroundColor Yellow
Write-Log "PASSO 3/5: Instalando Kali Linux..." "Yellow"
Write-Host "----------------------------------------" -ForegroundColor Yellow

$distros = wsl --list --quiet 2>$null
$kaliInstalled = $distros -match "kali"

if ($kaliInstalled) {
    Write-Log "Kali Linux ja instalado!" "Green"
} else {
    Write-Log "Instalando Kali Linux via WSL..." "Cyan"
    wsl --install -d kali-linux
    Write-Log "Kali Linux instalado!" "Green"
}

Write-Host ""

# PASSO 4: Configurar Kali e instalar ferramentas
Write-Host "----------------------------------------" -ForegroundColor Yellow
Write-Log "PASSO 4/5: Instalando ferramentas do Kali..." "Yellow"
Write-Host "----------------------------------------" -ForegroundColor Yellow

$setupScript = @'
#!/bin/bash
set -e

echo "=== Criando usuario cloudos ==="
useradd -m -s /bin/bash cloudos 2>/dev/null || true
echo "cloudos:cloudos123" | chpasswd
usermod -aG sudo cloudos 2>/dev/null || true
echo "cloudos ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/cloudos

echo "=== Atualizando sistema ==="
apt-get update -y

echo "=== Instalando ferramentas essenciais ==="
DEBIAN_FRONTEND=noninteractive apt-get install -y \
    nmap \
    nikto \
    sqlmap \
    hydra \
    john \
    hashcat \
    gobuster \
    dirb \
    wfuzz \
    netcat-openbsd \
    curl \
    wget \
    git \
    python3 \
    python3-pip \
    tor \
    privoxy \
    macchanger

echo "=== Instalando ferramentas adicionais ==="
DEBIAN_FRONTEND=noninteractive apt-get install -y \
    subfinder \
    nuclei \
    ffuf \
    whatweb \
    theharvester \
    searchsploit \
    fierce \
    dnsrecon \
    2>/dev/null || true

echo "=== Criando diretorios ==="
mkdir -p /home/cloudos_users
chmod 777 /home/cloudos_users
mkdir -p /root/.trash
chmod 777 /root/.trash

echo "=== Concluido! ==="
'@

try {
    Write-Log "Executando setup no Kali Linux..." "Cyan"
    $setupScript | wsl -d kali-linux -u root bash
    Write-Log "Ferramentas instaladas no Kali!" "Green"
} catch {
    Write-Log "Aviso ao configurar Kali: $($_.Exception.Message)" "Yellow"
}

Write-Host ""

# PASSO 5: Criar .wslconfig
Write-Host "----------------------------------------" -ForegroundColor Yellow
Write-Log "PASSO 5/5: Criando .wslconfig..." "Yellow"
Write-Host "----------------------------------------" -ForegroundColor Yellow

$wslConfig = @"
[wsl2]
memory=3GB
processors=2
swap=2GB
localhostForwarding=true
"@

$userConfigPath = Join-Path $env:USERPROFILE ".wslconfig"
$wslConfig | Out-File -FilePath $userConfigPath -Encoding UTF8 -Force
Write-Log "Arquivo .wslconfig gerado em $userConfigPath" "Green"

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "  INSTALACAO CONCLUIDA!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Log "WSL2: OK" "Green"
Write-Log "Kali Linux: OK" "Green"
Write-Log "Ferramentas: Nmap, SQLMap, Hydra, John, Nikto, Gobuster, etc." "Green"
Write-Host ""
Write-Host "REINICIE O COMPUTADOR PARA APLICAR OS RECURSOS DO WINDOWS!" -ForegroundColor Yellow
Write-Host ""

pause
