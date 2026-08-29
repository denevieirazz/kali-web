# CloudOS Native Windows Rewrite

## Decisão de arquitetura

CloudOS deixa de ser um shell web hospedado por um processo Windows. O produto passa a ser um runtime desktop Windows nativo.

O processo principal é `CloudOS.NativeShell.exe`.

## Linguagem de produto

- C++ em modo mais recente do toolset MSVC (`/std:c++latest`, tratado como trilha C++23 do projeto).
- Win32/COM/WinRT/DirectX são APIs de primeira classe.
- C só é permitido quando necessário para bibliotecas nativas de terceiros.
- PowerShell/CMD podem existir como automação de build/desenvolvimento, mas não como runtime obrigatório do CloudOS instalado.

## Stack removido do runtime principal

Os itens abaixo não podem ser requisito de boot, UI, window manager, terminal, filesystem ou process runtime:

- React
- Vite
- Node.js
- npm
- JavaScript
- TypeScript
- HTML
- CSS
- WebSocket para IPC local de subsistemas do SO
- HTTP para IPC local de subsistemas do SO
- WebView2 como shell do CloudOS
- Chromium como compositor/UI do CloudOS

Código legado dessas tecnologias pode permanecer no repositório durante a migração apenas como referência histórica. Ele não participa do boot nativo.

## Runtime alvo

```text
CloudOS.NativeShell.exe
|
+-- Shell / Desktop
|   +-- Win32 HWND
|   +-- DirectComposition
|   +-- Direct3D 11
|   +-- Direct2D
|   +-- DirectWrite
|
+-- Window Manager
|   +-- HWND discovery/correlation
|   +-- WinEvent hooks
|   +-- focus/z-order
|   +-- DPI/monitor topology
|   +-- native child hosting where valid
|   +-- GPU captured-surface compatibility where required
|
+-- Process Runtime
|   +-- CreateProcessW
|   +-- STARTUPINFOEX
|   +-- Job Objects
|   +-- process/token/integrity validation
|   +-- Named Pipes/shared memory for IPC
|
+-- Terminal
|   +-- ConPTY
|   +-- DirectWrite renderer
|   +-- PowerShell/cmd/WSL/Kali as child processes
|
+-- Filesystem
|   +-- Win32 file APIs
|   +-- NTFS semantics
|   +-- IFileOperation/Shell APIs where appropriate
|   +-- CloudOS Drive implemented natively
|
+-- WSL Runtime
|   +-- native process management
|   +-- ConPTY
|   +-- filesystem bridge
|
+-- Security
    +-- Windows tokens/integrity levels
    +-- Job containment
    +-- DPAPI where secrets are stored
    +-- fail-closed process/window ownership
```

## Ordem de implementação

### M0 - Native boot

Critério:

- `Iniciar CloudOS.cmd` inicia `CloudOS.NativeShell.exe`.
- Não inicia Node/Vite/WebView2.
- Shell cria HWND real e desenha desktop/taskbar/start com APIs Windows.
- CI Windows compila runtime + shell.

### M1 - Process kernel

Migrar para C++:

- launch catalog
- `CreateProcessW`/`STARTUPINFOEX`
- Job Objects
- process lifecycle
- integrity/session checks
- native app sessions
- named-pipe control plane

### M2 - Native compositor/window manager

Implementar:

- Direct3D 11 device compartilhado
- DirectComposition visual tree
- Direct2D/DirectWrite overlays
- HWND correlation via WinEvent
- snap/minimize/maximize/focus/z-order
- multi-monitor e Per-Monitor DPI v2
- compatibility policy por aplicativo

Nenhum pixel de aplicativo passa por JavaScript.

### M3 - Native terminal

Substituir xterm.js/PTY web por:

- ConPTY
- reader/writer assíncrono Win32
- parser VT nativo
- renderer DirectWrite
- PowerShell, cmd e WSL/Kali como processos filhos

### M4 - Native Files/Drive

Substituir file managers web por:

- Win32 filesystem
- Shell item APIs
- IFileOperation
- watchers nativos
- CloudOS Drive persistente

### M5 - Native system apps

Migrar Settings, Process Manager, System Monitor, installer UI e ferramentas do CloudOS para superfícies nativas.

### M6 - Remoção física do legado web

Somente depois de equivalência funcional:

- remover `frontend/`
- remover dependências Node/npm
- remover antigo Host WebView2
- remover scripts de Vite
- remover contratos WebMessage/WebSocket/HTTP que existiam apenas por causa do shell web

A remoção física ocorre por último para não apagar referência funcional antes de cada módulo ser substituído.

## Regra de compatibilidade Windows

CloudOS não tenta forçar todos os programas Windows por uma única técnica. O window runtime escolhe a estratégia nativa adequada:

1. HWND/child hosting quando o aplicativo aceita de forma segura.
2. DirectComposition/captured GPU surface para aplicações incompatíveis com reparenting/owner mutation.
3. gerenciamento externo controlado somente quando nenhuma superfície interna é tecnicamente possível.

As restrições de UAC, Secure Desktop, UIPI, processos de integridade superior, DRM/protected content, anti-cheat e isolamento de sessão continuam sendo boundaries reais do Windows e não devem ser contornadas.

## Regra de CI

O CI nativo deve falhar se:

- o launcher voltar a depender de Node/Vite/WebView2/PowerShell runtime;
- `CloudOS.NativeRuntime` ou `CloudOS.NativeShell` deixarem de compilar em Windows x64;
- o executável principal não for produzido;
- uma futura mudança recolocar UI web como dependência do boot.
