// scriptLabTemplates.js - Templates Táticos de Pentest para ScriptLab

export const SCRIPT_TEMPLATES = [
  {
    name: 'Port Scanner TCP',
    language: 'python',
    description: 'Scanner de portas simples e rápido usando Sockets.',
    code: `import socket
import sys
from concurrent.futures import ThreadPoolExecutor

target = "127.0.0.1"
ports = [21, 22, 80, 443, 8080, 3306, 5432]

print(f"[*] Iniciando scan em {target}...")

def scan_port(port):
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.settimeout(1.0)
        result = s.connect_ex((target, port))
        if result == 0:
            print(f"[+] Porta {port} Aberta!")
        s.close()
    except Exception as e:
        pass

with ThreadPoolExecutor(max_workers=10) as executor:
    executor.map(scan_port, ports)

print("[*] Scan concluído!")
`
  },
  {
    name: 'Banner Grabber',
    language: 'python',
    description: 'Coleta banners de serviços rodando em portas abertas.',
    code: `import socket

target = "127.0.0.1"
port = 22

print(f"[*] Conectando em {target}:{port}...")

try:
    s = socket.socket()
    s.settimeout(2.0)
    s.connect((target, port))
    banner = s.recv(1024).decode().strip()
    print(f"[+] Banner recebido:\n{banner}")
    s.close()
except Exception as e:
    print(f"[-] Erro: {e}")
`
  },
  {
    name: 'Fuzzer de Subdomínios',
    language: 'bash',
    description: 'Script Bash para testar subdomínios via DNS.',
    code: `#!/bin/bash
DOMAIN="example.com"
WORDLIST=("www" "mail" "api" "admin" "dev" "stage" "test" "vpn")

echo "[*] Testando subdomínios para $DOMAIN..."

for sub in "\${WORDLIST[@]}"; do
    target="$sub.$DOMAIN"
    ip=$(dig +short "$target" | head -n 1)
    if [ -n "$ip" ]; then
        echo "[+] Encontrado: $target -> $ip"
    fi
done

echo "[*] Concluído!"
`
  },
  {
    name: 'Requisição HTTP / Headers',
    language: 'python',
    description: 'Inspeção de cabeçalhos de resposta HTTP e cookies.',
    code: `import urllib.request

url = "http://httpbin.org/headers"

print(f"[*] Enviando requisição GET para {url}...")

try:
    req = urllib.request.Request(url, headers={'User-Agent': 'CloudOS-ScriptLab/1.0'})
    with urllib.request.urlopen(req) as response:
        print(f"[+] Status Code: {response.status}")
        print("\n--- Headers de Resposta ---")
        for key, val in response.getheaders():
            print(f"{key}: {val}")
        print("\n--- Corpo da Resposta ---")
        print(response.read().decode()[:500])
except Exception as e:
    print(f"[-] Erro: {e}")
`
  },
  {
    name: 'PowerShell Info Gatherer',
    language: 'powershell',
    description: 'Coleta de informações do sistema operacional via PowerShell.',
    code: `Write-Host "[*] Coletando Informações do Sistema..." -ForegroundColor Cyan

$os = Get-CimInstance Win32_OperatingSystem
$cpu = Get-CimInstance Win32_Processor
$cs = Get-CimInstance Win32_ComputerSystem

Write-Host "SO: $($os.Caption) ($($os.OSArchitecture))"
Write-Host "CPU: $($cpu.Name) ($($cpu.NumberOfCores) núcleos)"
Write-Host "RAM Total: $([math]::Round($cs.TotalPhysicalMemory / 1GB, 2)) GB"
Write-Host "Usuário Ativo: $env:USERNAME"
Write-Host "Hostname: $env:COMPUTERNAME"
Write-Host "[*] Concluído!" -ForegroundColor Green
`
  }
];
