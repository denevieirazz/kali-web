# CloudOS.NativeRuntime

`CloudOS.NativeRuntime` e o nucleo C++/Win32 do CloudOS.

Ele nao e uma ponte para React, Node, WebView2 ou um host gerenciado. O runtime e carregado diretamente pelo `CloudOS.NativeShell.exe` e expoe uma ABI C pequena e versionada para os subsistemas nativos.

## Responsabilidades atuais

- `CreateProcessW` suspenso e ownership por Job Object.
- encerramento fail-closed da arvore de processos contida.
- terminal nativo via ConPTY (`CreatePseudoConsole`).
- leitura, escrita e resize do pseudoconsole.
- descoberta de HWNDs top-level por `SetWinEventHook`.
- enumeracao e frame bounds reais via Win32/DWM.
- operacoes de foco/layout para compatibilidade Win32.
- acesso WSL por API nativa resolvida dinamicamente quando disponivel.

## ABI

A versao da ABI fica em `include/cloudos_native_runtime.h` e e validada pelo shell no boot. Uma DLL incompatível faz o shell falhar fechado antes de iniciar a interface.

## Limites do Windows

O runtime nao tenta contornar Secure Desktop/UAC, UIPI, anti-cheat, janelas protegidas, DRM, AppContainer ou outras fronteiras de seguranca do Windows. A arquitetura administra HWNDs reais em vez de depender de reparenting universal.
