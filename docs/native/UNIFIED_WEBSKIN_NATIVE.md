# CloudOS Unified WebSkin — Native Shell Visual Contract

## Objetivo

O CloudOS Shell V3 continua sendo um desktop environment Win32/C++ nativo. A antiga interface React/CSS não volta a controlar Desktop, Taskbar, Start, Files ou aplicativos do sistema. O que foi reutilizado é a **linguagem visual** do frontend antigo: paleta, materiais, espaçamento, tipografia, cantos, estados e hierarquia.

A regra de arquitetura é simples:

> **Funcionalidade e lifecycle ficam nativos. O frontend antigo funciona apenas como especificação visual.**

## Tokens oficiais

A fonte de verdade nativa fica em `native_theme.h`, namespace `CloudOS::WebSkin`, espelhando `frontend/src/index.css`:

- Background sólido: `#0a0a0f`
- Background primário: `#111118`
- Background secundário: `#1a1a24`
- Background terciário: `#22222e`
- Surface elevada: `#2a2a38`
- Accent: `#6366f1`
- Accent hover: `#818cf8`
- Accent active: `#4f46e5`
- Texto primário: `#f0f0f5`
- Texto secundário: `#a0a0b8`
- Texto terciário: `#6b6b82`
- Radius: 4 / 8 / 12 / 16 DIP

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

## Superfícies cobertas neste passe

### Desktop

- Fallback wallpaper refeito com gradiente do WebSkin.
- Removido o grande círculo opaco que dominava o canto superior direito.
- Glows ambientes mais discretos.
- Ícones/labels com escala e espaçamento levemente maiores.
- Métricas e identificação de workspace seguem o mesmo sistema tipográfico.

### Taskbar / AppBar

- Continua uma AppBar real via `SHAppBarMessage`.
- Altura aumentada para 64 DIP.
- Start e pins maiores.
- Workspaces viraram pills visuais em vez de botões de debug.
- Tarefas recebem cards escuros e estado accent quando ativas.
- Área rápida usa `Som · Rede` e tipografia mais legível.

### Start

- Mantém o indexador nativo de programas Windows + catálogo CloudOS.
- Mantém pesquisa, teclado, MRU, reindexação, energia e Central de Comandos.
- Usa cards, accent, owner/custom draw e material transient.
- Não usa WebView para renderizar o Start.

### Quick Settings

- Mantém `IAudioEndpointVolume` e `GetSystemPowerStatus` reais.
- Flyout sem borda Win32 pesada.
- Botões owner-draw e grade inspirada no frontend antigo.
- Volume, mute, energia e atalhos Windows continuam operacionais.

### Notification Center

- Histórico nativo preservado.
- ListView escura/custom-draw.
- Botão danger para limpar histórico.
- Flyout acrylic/transient.

### Settings

- Mantém persistência no Registry e regra de tiling manual.
- Edit sem `WS_EX_CLIENTEDGE` clássico.
- Botões nativos owner-draw.
- Mica/main backdrop.

### Calculator

- Toda a lógica matemática continua nativa.
- Display escuro.
- Teclas em cards.
- Operadores/equal em accent.
- Clear em danger.

### Notepad

- Toda a leitura/escrita UTF-8 continua nativa.
- Editor escuro em Cascadia Mono.
- Toolbar owner-draw.
- Salvar em accent e limpar em danger.

### System Monitor

- Telemetria continua baseada em APIs reais (`GetSystemTimes`, `GlobalMemoryStatusEx`, Toolhelp).
- Cards e progress bars passam a usar os tokens do WebSkin.

### Files

- Chrome do CloudOS agora usa paleta escura e Mica.
- Sidebar/toolbar/address/fallback list usam os mesmos tokens do shell.
- `IExplorerBrowser` continua sendo o provider de namespace Windows/WSL; o CloudOS não substitui APIs Shell por HTML.

### File Operations / ZIP e Command Center

Essas janelas continuam com a implementação funcional atual, mas recebem o `WindowSkinSubclass` compartilhado por meio de `DarkWindow(window_)`, removendo o fundo branco e client edges legados onde aplicável, sem alterar os contratos de `IFileOperation`, progress sink, ZIP/tar ou ações do sistema.

## Não-regressões

O WebSkin não pode:

1. Reintroduzir WebView/React como Desktop ou Start principal.
2. Reintroduzir `SetParent` para sequestrar janelas externas.
3. Ligar tiling automaticamente.
4. Remover AppBar real da taskbar.
5. Remover DWM thumbnails.
6. Alterar copy/move/ZIP/recovery/watchdog apenas para facilitar o visual.
7. Voltar a `WS_EX_CLIENTEDGE` como identidade visual das superfícies principais.

## Próximas fronteiras visuais/UX

Depois deste passe, os próximos ganhos deixam de ser apenas skin e passam a ser comportamento:

- agrupamento/context menu/pins reordenáveis da taskbar;
- Snap Layout flyout nas titlebars CloudOS;
- tabs/thumbnails/properties no Files;
- Wi-Fi/Bluetooth/media/brilho realmente inline no Quick Settings;
- seleção rubber-band e posições persistentes no Desktop;
- animações de abertura/fechamento coordenadas com DWM.
