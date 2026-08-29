# CloudOS Native architecture

## Product boundary

```text
Iniciar CloudOS.cmd
        |
        v
MSBuild (development only)
        |
        v
CloudOS.exe
   |         \
   |          +--> Win32/DWM/Common Controls/Direct2D/DirectWrite
   |
   +--> CloudOS.NativeRuntime.dll
             |
             +--> CreateProcessW + Job Objects
             +--> ConPTY
             +--> SetWinEventHook / HWND inventory
             +--> WSL platform APIs
```

Nao existe browser engine, DOM, frontend JavaScript ou servidor local entre o usuario e as APIs do Windows.

## Shell

`CloudOS.exe` possui tres superficies principais controladas pelo proprio processo: desktop, taskbar e menu Iniciar. As ferramentas internas (Terminal, Arquivos, Processos, Aplicativos e Executar) tambem sao janelas Win32 nativas.

O Window Manager observa HWNDs top-level reais e mantem metadados de workspace/floating. Aplicativos externos nao sao convertidos em iframes, WebViews ou bitmaps interativos. Isso remove a antiga incompatibilidade estrutural de tentar encaixar qualquer aplicativo dentro de uma superficie web.

## Window Manager

- inventario inicial de HWND;
- eventos create/show/hide/destroy/foreground/location via runtime;
- workspaces 1-4;
- taskbar baseada nas janelas do workspace atual;
- tiling master/stack por monitor;
- floating por janela;
- snap por monitor work area;
- foco anterior/proximo;
- restauracao de janelas ocultadas por workspace no shutdown;
- borda DWM para indicar janela ativa quando suportado.

## Terminal

O terminal visual usa ConPTY diretamente pelo `CloudOS.NativeRuntime.dll`. A UI recebe bytes do pseudo console, decodifica UTF-8, trata a sequencia VT basica necessaria e desenha texto nativamente. Teclado, setas, Home/End/Delete, clipboard e resize sao enviados ao ConPTY sem xterm.js.

## Windows + WSL

O shell trata Windows e WSL como capacidades do mesmo desktop. O File Manager navega volumes Windows e shares WSL. O perfil Kali usa `wsl.exe -d kali-linux` apenas para abrir a sessao interativa ConPTY quando a distro estiver registrada.

## Limites deliberados

CloudOS nao tenta violar seguranca do Windows. Secure Desktop/UAC, UIPI, protected processes, DRM, anti-cheat, AppContainer, sessoes isoladas e aplicativos com politicas especiais podem limitar foco, manipulacao ou visibilidade. Esses casos sao tratados como limites do sistema operacional, nao como motivo para reintroduzir um renderer web.
