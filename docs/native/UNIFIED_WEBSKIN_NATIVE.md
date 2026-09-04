# CloudOS Unified WebSkin — Native Shell Visual Contract

## Objetivo

O CloudOS Shell continua sendo um desktop environment Win32/C++ nativo, com Flutter como cliente de apresentação integrado. A antiga interface React/CSS foi aposentada e seu código de desktop não faz mais parte da árvore ativa. React não volta a controlar Desktop, Taskbar, Start, Files ou aplicativos do sistema.

A linguagem visual que já havia sido absorvida pelo shell foi congelada em **tokens visuais nativos** em `native_theme.h`. A partir daqui, esses tokens são a fonte de verdade; eles não dependem mais de arquivos CSS do frontend removido.

A regra de arquitetura é simples:

> **Funcionalidade e lifecycle ficam nativos. Flutter apresenta o produto; React/CSS não é mais uma implementação do desktop.**

## Tokens oficiais

A fonte de verdade fica em `desktop/CloudOS.NativeShell/src/native_theme.h`, namespace `CloudOS::WebSkin`, combinada com `DesignV12`. Os valores podem evoluir dentro do contrato visual nativo sem precisar espelhar CSS legado.

## Infraestrutura visual compartilhada

O WebSkin fornece primitivas reutilizáveis para não repetir RGBs e estilos em cada janela:

- `PaintWindowBackground` — fundo em gradiente escuro.
- `DrawRoundedPanel` — cards/surfaces arredondadas.
- `PaintOwnerDrawButton` — botão nativo com estados neutral/accent/danger.
- `PrepareEdit` — remove `WS_EX_CLIENTEDGE` legado e ativa tema escuro.
- `PrepareListView` — lista escura e double-buffered.
- `HandleListViewCustomDraw` — seleção/hover coerentes.
- `WindowSkinSubclass` — fallback compartilhado para fundo, STATIC, EDIT e LISTBOX em janelas que ainda usam controles clássicos.
- `ApplyWebFlyoutMaterial` — material transient/acrylic para Start, Quick Settings e Notification Center.
- `ApplyWebWindowMaterial` — Mica/main-window para apps persistentes.

Essas primitivas são uma camada de **apresentação Win32**. Elas não alteram o WindowManager, AppBars, DWM thumbnails, COM file operations, recovery, watchdog ou launch policy.

## Superfícies cobertas

### Desktop

- Fallback wallpaper usa o sistema de tokens nativos.
- Glows ambientes discretos.
- Ícones/labels e métricas seguem o sistema tipográfico nativo.
- Workspace continua sob autoridade do Window Manager nativo.

### Taskbar / AppBar

- Continua uma AppBar real via `SHAppBarMessage`.
- Start, pins, workspaces, tarefas e área rápida permanecem nativos.

### Start

- Mantém o indexador nativo de programas Windows + catálogo CloudOS.
- Mantém pesquisa, teclado, MRU, reindexação, energia e Central de Comandos.
- Usa cards, accent, owner/custom draw e material transient.
- Não usa WebView para renderizar o Start.

### Quick Settings / Notification Center

- Mantêm backends e estado nativos.
- Flyouts e controles usam o tema compartilhado.

### Settings / Calculator / Notepad / System Monitor

- Lógica funcional continua nativa.
- A camada visual consome os tokens do WebSkin.

### Files

- Chrome do CloudOS usa a paleta nativa.
- `IExplorerBrowser` continua sendo o provider de namespace Windows/WSL; o CloudOS não substitui APIs Shell por HTML.

### Browser

- WebView2 permanece permitido exclusivamente no Navegador CloudOS.
- WebView2 não é renderer do Desktop, Start, Taskbar ou Files.

## Não-regressões

O WebSkin não pode:

1. Reintroduzir WebView/React como Desktop ou Start principal.
2. Recriar `frontend/src`, Vite ou servidor React como segunda UI do CloudOS.
3. Reintroduzir `SetParent` genérico para sequestrar janelas externas fora do contrato de contenção revisado.
4. Ligar tiling automaticamente.
5. Remover AppBar real da taskbar.
6. Remover DWM thumbnails.
7. Alterar copy/move/ZIP/recovery/watchdog apenas para facilitar o visual.
8. Voltar a `WS_EX_CLIENTEDGE` como identidade visual das superfícies principais.

A interface React/CSS antiga **não volta a controlar Desktop, Taskbar, Start**. Seu histórico permanece no Git, não como código ativo no produto.
