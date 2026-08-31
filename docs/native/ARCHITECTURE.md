# Arquitetura atual — CloudOS Native Shell

## 1. Visão geral

CloudOS é um shell desktop nativo sobre Windows. Ele não substitui kernel, drivers, Win32, DWM ou os serviços do Windows. A camada CloudOS fornece Desktop, Taskbar, Start, flyouts, Window Manager, workspaces, Files e apps first-party e integra capacidades Windows + Linux/WSL por boundaries explícitas.

A autoridade do desktop é C++/Win32:

```text
CloudOS.NativeShell (C++/Win32)
    └─ CloudOS.exe
         ├─ Desktop / Taskbar / Start
         ├─ Window Manager / Workspaces
         ├─ Quick Settings / Notification Center / System Center
         ├─ Files / Browser / Apps first-party
         ├─ Unified Integration V16 (Windows + WSL/Linux)
         ├─ Health V9 + Lifecycle V10
         └─ CloudOS.NativeRuntime.dll
```

WebView2 existe onde é apropriado, principalmente no Navegador CloudOS. O antigo desktop React não participa do build nativo.

## 2. Grafo de processos e autoridade

### Execução normal

```text
launcher
  └─ CloudOS.Supervisor.exe          [V11 — recovery]
       └─ CloudOS.exe --supervised   [shell/UI]
            └─ CloudOS.NativeRuntime.dll
```

Sob `--supervised`, o watchdog embutido não cria um recovery loop concorrente. Supervisor observa readiness/heartbeat V9, reinicia com orçamento limitado e mantém Explorer como fallback.

### Instalação V13

```text
%LOCALAPPDATA%\CloudOS\NativeShell\
  ├─ state\deployment-v13.json
  ├─ state\deployment-v13.journal.json
  ├─ versions\<versão verificada>\
  │    ├─ CloudOS.exe
  │    ├─ CloudOS.NativeRuntime.dll
  │    ├─ CloudOS.Supervisor.exe
  │    └─ cloudos-native-manifest.json
  └─ tools\...
```

Uma versão V13 só é publicada depois de manifesto, tamanho, SHA256 e Supervisor self-test. A versão anterior pode ser last-known-good.

### Ativação opt-in V14

```text
HKCU\Software\Microsoft\Windows NT\CurrentVersion\Winlogon\Shell
  └─ comando estável V14
       └─ <install-root>\shell-v14\CloudOS.ShellEntry.V14.cmd
            └─ deployment-v13.json
                 └─ versions\<active>\CloudOS.Supervisor.exe
                      └─ CloudOS.exe --supervised
```

Instalar/atualizar não ativa automaticamente o shell. V14 salva presença/tipo/dado não expandido do `Shell`, restaura exatamente esse snapshot e usa journal para recuperação. Hosted CI só escreve em HKCU sandbox.

## 3. Componentes de processo

### `desktop/CloudOS.NativeShell`

Entry point compilado: `src/main_shell_v2.cpp`.

Grupos principais:

- Desktop: wallpaper, namespace, drop target, menu de contexto.
- Shell chrome: Taskbar, Start, Quick Settings, Notification Center, toast.
- Window management: HWND events, workspaces, Snap, DWM previews.
- Control plane: System Center, tray, controles.
- Files: Windows/CloudOS Drive/WSL filesystem.
- Session: continuity, recovery e lifecycle.
- Apps: Browser, Terminal, Notepad, Calculator, Projects, Run.
- V16: downloads, inventory/package management Windows e WSLg/Linux.

Veja `CODEMAP.md`.

### `desktop/CloudOS.NativeRuntime`

DLL nativa: runtime base, ConPTY, eventos de janela e WSL API de baixo nível.

### `desktop/CloudOS.NativeRecovery`

Produz `CloudOS.Supervisor.exe`, autoridade externa V11.

### `desktop/CloudOS.NativeCommon`

Protocolos compartilhados; alterações exigem cuidado com ABI/mappings/messages.

## 4. Health V9

Invariantes:

- snapshot pointer-free de 96 bytes;
- mapping `Local\CloudOS.NativeShell.Health.v9`;
- event `Local\CloudOS.NativeShell.Ready.v9`;
- heartbeat produzido pela UI thread;
- Desktop `CloudOS.NativeShell.Desktop.v2`.

## 5. Lifecycle V10

Trata suspend/resume, display/AppBar/workarea, WTS/RDP checkpoints/refresh, retry WTS e single-instance. Hosted CI usa probes determinísticos e não prova transporte/hardware físico.

## 6. Supervisor V11

1. inicia `CloudOS.exe --supervised`;
2. espera Ready;
3. observa heartbeat;
4. distingue shutdown normal de falha/hang;
5. aplica restart budget/backoff;
6. pede graceful exit antes de terminate;
7. usa Explorer como fallback quando necessário.

## 7. Performance/Visual V12

Princípios:

- event-driven;
- `WM_PAINT` só desenha estado cacheado;
- filesystem/Shell APIs caras fora do paint;
- backbuffer reutilizado;
- dirty regions;
- workers para trabalho lento;
- superfícies escondidas não fazem refresh caro;
- telemetria sem conteúdo pessoal.

## 8. Deployment V13

`CloudOS.Deployment.V13.psm1` é autoridade de install/update/repair/rollback/uninstall por usuário. Não ativa Winlogon.

## 9. Shell Activation V14

`CloudOS.ShellActivation.V14.psm1` é a autoridade moderna de ativação opt-in. Não confundir com `configure-cloudos-shell-launcher.ps1` (WESL legado/administrativo). V14 permanece current-user e não usa HKLM/Userinit/Run/serviço/tarefa como atalho.

## 10. Repository Clarity V15

`AGENTS.md`, `docs/native/CODEMAP.md`, `VALIDATION.md` e `test-native-contract-suite.ps1` tornam as fontes de verdade explícitas. Reorganização lógica tem preferência sobre churn físico sem ganho arquitetural.

## 11. Unified Windows + Linux Integration V16

A autoridade é:

```text
native_integration_v16.*
    ├─ Windows installed-app inventory [registry read-only]
    ├─ WinGet command boundary
    ├─ WSL distro discovery
    ├─ Linux .desktop discovery
    ├─ WSLg gtk-launch
    └─ apt/snap/flatpak removal mapping
```

Surfaces consomem essa boundary em vez de duplicar integração.

### Browser/download

```text
WebView2 DownloadStarting
   ↓
native_browser_window.cpp
   ↓
native_folder_picker_v16.*
   ├─ Windows known folders
   └─ \\wsl.localhost\...
   ↓
ICoreWebView2DownloadStartingEventArgs::ResultFilePath
```

WebView2 continua sendo download engine; CloudOS controla a experiência/destino.

### Files

Files V5 já expõe Windows, CloudOS Drive e `\\wsl.localhost\`. Não existe um segundo file manager Linux.

### Apps

`native_apps_window.*` combina:

- apps first-party;
- Start Menu/PATH;
- inventário de uninstall Windows;
- GUI apps Linux de `/usr/share/applications`.

Windows install usa WinGet em Terminal visível. Linux install V16 usa apt/WSL em Terminal visível. Removal usa uninstall registrado/WinGet no Windows e apt/snap/flatpak quando mapeável no Linux.

### Desktop/Start

`native_desktop_model_v12.h` agrega user Desktop + Public Desktop + launchers Linux gerenciados. Change notifications atualizam Desktop sem polling. Mudança em Programs/CommonPrograms chama `NativeStartIndex::RefreshAsync()`.

Apps Linux são materializados como `.lnk` gerenciados em `%LOCALAPPDATA%\CloudOS\IntegrationV16\LinuxShortcuts`, apontando para WSLg `gtk-launch`; o CloudOS não modifica os `.desktop` originais.

### Window Manager

WSLg expõe GUI Linux como janelas integradas ao desktop Windows. O CloudOS usa o mesmo HWND/DWM Window Manager; não há um compositor/window manager Linux concorrente dentro do shell.

### Defaults e segurança

V16 **não** altera default apps/file associations silenciosamente, não escreve HKLM/package registry, não guarda senha sudo, não ignora UAC e não apaga pasta de app para fingir uninstall.

Detalhes: `UNIFIED_INTEGRATION_V16.md`.

## 12. Estado e persistência

Dono claro por domínio:

- deployment/update: V13 state/journal;
- shell activation: V14 state/journal;
- preferences/runtime: módulo nativo correspondente;
- workspaces/continuity: serviços próprios;
- release integrity: manifesto/fingerprint/hashes;
- V16 Linux launcher cache: `%LOCALAPPDATA%\CloudOS\IntegrationV16\LinuxShortcuts` (derivado, não fonte de verdade).

Não crie um segundo estado autoritativo para a mesma verdade sem migração definida.

## 13. Legado/compatibilidade

`frontend/`, `backend/`, `desktop/CloudOS.Host`, Bootstrap e testes WPF permanecem para compatibilidade/caracterização. Para o desktop atual:

```text
não usar React como autoridade do Desktop
não usar WPF Host como autoridade do shell
não construir frontend para gerar CloudOS.exe
não adicionar WebView2 ao Desktop principal
```

## 14. Direção de dependência

Prefira:

```text
UI surface
  ↓
service/model/boundary explícita
  ↓
platform/runtime
  ↓
Windows / WSL APIs
```

Para V16:

```text
Browser / Apps / Desktop / Files
  ↓
native_integration_v16.*  (quando é integração Windows↔Linux/package)
  ↓
Win32 / Registry read-only / WinGet / WSL / WSLg
```

Evite surface fazendo I/O no paint, módulos alterando estado global alheio, scripts de install alterando shell como side effect e recovery dependendo da própria UI quebrada.

## 15. Flutter Presentation & Native Bridge (V19 / V20)

CloudOS V19 introduziu a camada de apresentação Flutter (`desktop/CloudOS.FlutterShell`), e a V20 estabelece a integração com o core nativo C++ através de um canal tipado `MethodChannel` (`cloudos/native/v19`).

```text
Flutter UI (Dart)
  ↓
CloudOSBridge (loadApps, loadSystemSnapshot, launchApp, setVolume, setBrightness)
  ↓ [cloudos/native/v19]
CloudOSFlutterBridgeV20 (C++ Runner)
  ↓
NativeIntegrationV16 / NativeStartIndex / Win32 Core
```

- Flutter é estritamente camada de apresentação visual (consumidor).
- Chamadas a `wsl.exe`, `powershell.exe`, Registry e Win32 APIs ocorrem exclusivamente no C++.
- Dart envia apenas identificadores tipados (`id`), e o C++ resolve o target com segurança.

## 16. Leitura recomendada

- `docs/native/FLUTTER_NATIVE_BRIDGE_V20.md`
- `docs/native/CODEMAP.md`
- `docs/native/UNIFIED_INTEGRATION_V16.md`
- `docs/native/VALIDATION.md`
- `AGENTS.md`
- `scripts/native/README.md`
- `desktop/CloudOS.NativeShell/src/README.md`
