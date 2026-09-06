# CloudOS Native Shell — Modern Desktop Shell & System Runtime

CloudOS Native Shell é um ambiente desktop de alta performance para Windows baseado em uma arquitetura híbrida moderna: camada de apresentação em **Flutter Desktop (C++/Dart)** acoplada a um núcleo nativo de autoridade em **C++/Win32**, **System Broker IPC (Protocolo V21/V22)**, **Terminal ConPTY**, integração profunda com **WSL** e salvaguardas rigorosas contra tela preta com **fallback automático para o Windows Explorer**.

O Windows continua responsável pelo kernel, drivers, DWM, subsistema de segurança, Win32 e serviços do sistema operacional. O CloudOS provê a experiência completa de Desktop, Taskbar, Dock, Start Menu, Window Manager com contenção Win32, Gerenciador de Arquivos transacional, painéis de controle do sistema e ciclo de vida supervisionado em modo usuário.

> Para agentes de IA e desenvolvedores: consulte [`AGENTS.md`](AGENTS.md), [`docs/PROJECT_STATUS_MASTER.md`](docs/PROJECT_STATUS_MASTER.md), [`docs/native/ARCHITECTURE.md`](docs/native/ARCHITECTURE.md) e [`docs/native/CODEMAP.md`](docs/native/CODEMAP.md).

---

## 1. Arquitetura do Sistema

```text
┌────────────────────────────────────────────────────────────────────────┐
│               Camada de Apresentação (Flutter Desktop Shell)           │
│  cloudos_flutter_shell.exe (Desktop, Taskbar, Dock, Start, Files, etc) │
└───────────────────────┬───────────────────────────┬────────────────────┘
                        │ Canal Nativo (v19/v20)    │ Named Pipe IPC (v21/v22)
┌───────────────────────▼──────────┐    ┌───────────▼────────────────────┐
│ Camada de Autoridade Nativa C++  │    │  System Broker C++/Win32       │
│ CloudOS.exe + NativeRuntime.dll  │    │  CloudOS.SystemBroker.exe      │
│  - Enumeração e Rehoming Win32   │    │  - ConPTY Terminal Host (x32)  │
│  - Captura e DPI Multi-Monitor   │    │  - Áudio CoreAudio & Sistema   │
│  - Memória Compartilhada / IPC   │    │  - WSL, Apps, Files Provider   │
└───────────────────────▲──────────┘    └────────────────────────────────┘
                        │
┌───────────────────────┴────────────────────────────────────────────────┐
│             Supervisão de Ciclo de Vida e Recuperação Segura           │
│  CloudOS.Supervisor.exe  (Watchdog / Heartbeat / Crash Loop Gate)      │
│  CloudOS.ShellBootstrap.exe  (Detecção de Sessão / Mutex Único)        │
│  CloudOS.Recovery.exe  (Ferramenta Standalone de Recuperação e Status) │
│                                                                        │
│                      FALLBACK DE EMERGÊNCIA:                           │
│                      explorer.exe (Windows Shell Oficial)              │
└────────────────────────────────────────────────────────────────────────┘
```

---

## 2. Componentes e Estrutura de Diretórios

```text
desktop/
├── CloudOS.FlutterShell/       # Apresentação Flutter (Dart / C++ Runner)
├── CloudOS.NativeShell/       # CloudOS.exe (Shell e Window Manager Win32)
├── CloudOS.NativeRuntime/     # CloudOS.NativeRuntime.dll (Core C++)
├── CloudOS.SystemBroker/      # CloudOS.SystemBroker.exe (Broker IPC V21/V22)
├── CloudOS.BrokerProbe/       # CloudOS.BrokerProbe.exe (Diagnóstico de IPC)
├── CloudOS.NativeRecovery/    # CloudOS.Supervisor.exe (Supervisor Watchdog)
├── CloudOS.NativeShellBootstrap/ # CloudOS.ShellBootstrap.exe (Bootstrap Shell)
├── CloudOS.NativeRecoveryTool/   # CloudOS.Recovery.exe (CLI de Recuperação)
└── CloudOS.NativeCommon/      # Protocolos compartilhados, ABI e tipos

dist/CloudOS/                  # Pacote de release (33 arquivos íntegros)
scripts/installer/             # Pipeline de instalação, startup e manutenção
scripts/native/                # Contratos, automação e validação de engenharia
docs/                          # Especificações técnicas e manuais de operação
```

---

## 3. Diretriz Absoluta de Segurança: GATE 0

O CloudOS foi projetado sob a garantia de **Risco Zero de Tela Preta**:

- **Winlogon Shell Oficial:** O valor padrão `HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon\Shell` permanece permanentemente configurado como `explorer.exe`.
- **Userinit Intacto:** O valor `HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon\Userinit` permanece intacto (`C:\WINDOWS\system32\userinit.exe,`).
- **Confinamento em Modo Usuário:** Zero drivers de kernel, zero serviços privilegiados globais.
- **Substituição Permanente de Shell (Gate 0):** Desativada por padrão em desenvolvimento e testes automatizados. A ativação permanente é estritamente opt-in por usuário e monitorada por watchdog com reversão automática para `explorer.exe` se houver falhas consecutivas.
- **Ferramenta de Recuperação Standalone:** `CloudOS.Recovery.exe restore` pode ser invocada via Task Manager (Ctrl+Shift+Esc) em caso de qualquer emergência, restaurando instantaneamente o Explorer.

---

## 4. Compilação e Empacotamento

### Pré-requisitos
- Windows 10/11 x64
- Visual Studio 2022 / Build Tools com suporte a Desktop C++
- Flutter SDK 3.x (canal estável)
- PowerShell 7 (`pwsh`)
- Windows SDK e WebView2 Runtime

### Compilar Componentes Nativos (Release x64)
```powershell
scripts\native\build-cloudos-native.cmd Release
```

### Compilar Shell Flutter (Release x64)
```powershell
cd desktop\CloudOS.FlutterShell
flutter build windows --release
```

### Pipeline Unificado de Release (RC1.2)
Para compilar nativo, Flutter, empacotar e gerar o instalador oficial Inno Setup:
```powershell
pwsh -NoProfile -File scripts/release/build-rc.ps1
```

O instalador oficial será gerado em `dist\releases\21.0.0-rc.1.2\CloudOS-Setup-21.0.0-rc.1.2-x64.exe` com seu respectivo `SHA256SUMS.txt`.

Consulte a documentação completa:
- [Guia de Instalação](docs/INSTALL.md)
- [Modelo de Segurança](docs/SECURITY_MODEL.md)
- [Política de Privacidade](docs/PRIVACY.md)
- [Atualizações e Rollback](docs/UPDATES.md)
- [Recuperação e Gate 0](docs/RECOVERY.md)

---

## 5. Suíte Completa de Testes Automatizados

O CloudOS conta com verificação automatizada em múltiplas camadas de engenharia:

```powershell
# 1. Análise estática do Flutter Shell (0 issues)
flutter analyze desktop/CloudOS.FlutterShell

# 2. Testes de widgets e apresentação Flutter (151/151 PASS)
flutter test desktop/CloudOS.FlutterShell

# 3. Contratos de arquitetura nativa C++ (49/49 PASS)
pwsh -NoProfile -File scripts/native/test-native-contract-suite.ps1

# 4. Contratos de instalador, integridade e rollback (5/5 PASS)
pwsh -NoProfile -File scripts/installer/test-all-installer-contracts.ps1

# 5. Contratos de inicialização segura per-user HKCU\Run (5/5 PASS)
pwsh -NoProfile -File scripts/installer/test-all-startup-contracts.ps1

# 6. Contratos de substituição de shell e recuperação (10/10 PASS)
pwsh -NoProfile -File scripts/installer/test-all-shell-contracts.ps1

# 7. Self-test do System Broker (51 asserções PASS)
& "desktop\CloudOS.NativeShell\bin\Release\CloudOS.SystemBroker.exe" --self-test

# 8. Smoke test de IPC e barramento de eventos
pwsh -NoProfile -File scripts/native/run-system-broker-smoke-v21.ps1
```

---

## 6. Instalação e Inicialização

### Instalação Limpa com Inicialização Automática Segura (Etapa 10)
```powershell
pwsh -NoProfile -File scripts/installer/CloudOS.Maintenance.ps1 -Action install -PackageDir dist\CloudOS -EnableStartup
```
A aplicação é instalada em `%LOCALAPPDATA%\Programs\CloudOS` com atalhos no Menu Iniciar e registro seguro em `HKCU\Software\Microsoft\Windows\CurrentVersion\Run`.

### Diagnóstico de Integridade e Status de Recuperação
```powershell
& "$env:LOCALAPPDATA\Programs\CloudOS\CloudOS.Recovery.exe" status
& "$env:LOCALAPPDATA\Programs\CloudOS\CloudOS.Recovery.exe" verify
```

### Desinstalação Limpa
```powershell
pwsh -NoProfile -File scripts/installer/CloudOS.Maintenance.ps1 -Action uninstall
```
Remove completamente arquivos, atalhos, entradas de inicialização e registros de desinstalação, preservando o Windows Explorer oficial intacto.
